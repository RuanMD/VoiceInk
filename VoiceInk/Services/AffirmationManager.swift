import SwiftUI
import AppKit

enum DisplayTarget: String, CaseIterable {
    case main      = "main"
    case secondary = "secondary"
    case all       = "all"

    var label: String {
        switch self {
        case .main:      return "Principal"
        case .secondary: return "Secundário"
        case .all:       return "Ambos"
        }
    }

    var icon: String {
        switch self {
        case .main:      return "macbook"
        case .secondary: return "display"
        case .all:       return "display.2"
        }
    }
}

enum ScheduleMode: String, CaseIterable {
    case interval    = "interval"
    case clockAligned = "clockAligned"

    var label: String {
        switch self {
        case .interval:     return "Contínuo"
        case .clockAligned: return "Relógio"
        }
    }

    var icon: String {
        switch self {
        case .interval:     return "timer"
        case .clockAligned: return "clock.badge.checkmark.fill"
        }
    }

    var description: String {
        switch self {
        case .interval:     return "Conta o tempo a partir da última exibição"
        case .clockAligned: return "Dispara nos minutos exatos (ex: 10:00, 10:15, 10:30...)"
        }
    }
}

enum PlaybackMode: String, CaseIterable {
    case sequential = "sequential"
    case shuffled   = "shuffled"

    var label: String {
        switch self {
        case .sequential: return "Em ordem"
        case .shuffled:   return "Aleatório"
        }
    }

    var icon: String {
        switch self {
        case .sequential: return "list.number"
        case .shuffled:   return "shuffle"
        }
    }
}

enum AffirmationTrigger: String, CaseIterable {
    case onTimer = "timer"
    case onWake  = "wake"
    case both    = "both"

    var label: String {
        switch self {
        case .onTimer: return "Por intervalo"
        case .onWake:  return "Ao acordar tela"
        case .both:    return "Ambos"
        }
    }

    var icon: String {
        switch self {
        case .onTimer: return "clock.fill"
        case .onWake:  return "sun.max.fill"
        case .both:    return "sparkles"
        }
    }
}

class AffirmationManager: ObservableObject {
    static let shared = AffirmationManager()

    @Published var messages: [AffirmationMessage] = []
    @Published var intervalMinutes: Int = 60
    @Published var isEnabled: Bool = false
    @Published var trigger: AffirmationTrigger = .onTimer
    @Published var displayTarget: DisplayTarget = .main
    @Published var playbackMode: PlaybackMode = .shuffled
    @Published var scheduleMode: ScheduleMode = .interval

    private var scheduledTimer: Timer?
    private var popupWindows: [NSPanel] = []
    private var dismissTimer: Timer?
    private var isScreenAwake = true
    private var shownIDs: Set<UUID> = []

    private let messagesKey    = "affirmationMessages"
    private let intervalKey    = "affirmationIntervalMinutes"
    private let enabledKey     = "affirmationEnabled"
    private let triggerKey     = "affirmationTrigger"
    private let displayKey     = "affirmationDisplayTarget"
    private let playbackKey    = "affirmationPlaybackMode"
    private let scheduleModeKey = "affirmationScheduleMode"

    private init() {
        loadFromStorage()
        setupScreenObservers()
        if isEnabled && trigger != .onWake {
            startTimer()
        }
    }

    // MARK: - Persistence

    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: messagesKey),
           let decoded = try? JSONDecoder().decode([AffirmationMessage].self, from: data) {
            messages = decoded
        }
        intervalMinutes = UserDefaults.standard.integer(forKey: intervalKey)
        if intervalMinutes == 0 { intervalMinutes = 60 }
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        if let raw = UserDefaults.standard.string(forKey: triggerKey),
           let t = AffirmationTrigger(rawValue: raw) {
            trigger = t
        }
        if let raw = UserDefaults.standard.string(forKey: displayKey),
           let d = DisplayTarget(rawValue: raw) {
            displayTarget = d
        }
        if let raw = UserDefaults.standard.string(forKey: playbackKey),
           let p = PlaybackMode(rawValue: raw) {
            playbackMode = p
        }
        if let raw = UserDefaults.standard.string(forKey: scheduleModeKey),
           let s = ScheduleMode(rawValue: raw) {
            scheduleMode = s
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: messagesKey)
        }
        UserDefaults.standard.set(intervalMinutes, forKey: intervalKey)
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        UserDefaults.standard.set(trigger.rawValue, forKey: triggerKey)
        UserDefaults.standard.set(displayTarget.rawValue, forKey: displayKey)
        UserDefaults.standard.set(playbackMode.rawValue, forKey: playbackKey)
        UserDefaults.standard.set(scheduleMode.rawValue, forKey: scheduleModeKey)
    }

    // MARK: - Messages

    func addMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages.append(AffirmationMessage(text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        save()
    }

    func deleteMessage(at offsets: IndexSet) {
        messages.remove(atOffsets: offsets)
        save()
    }

    func toggleMessage(_ message: AffirmationMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index].isEnabled.toggle()
            save()
        }
    }

    func updateMessage(_ message: AffirmationMessage, newText: String) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index].text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            save()
        }
    }

    // MARK: - Timer

    func setEnabled(_ value: Bool) {
        isEnabled = value
        save()
        if value {
            if trigger != .onWake { startTimer() }
        } else {
            stopTimer()
        }
    }

    func setDisplayTarget(_ d: DisplayTarget) {
        displayTarget = d
        save()
    }

    func setScheduleMode(_ mode: ScheduleMode) {
        scheduleMode = mode
        save()
        if isEnabled && trigger != .onWake {
            startTimer()
        }
    }

    func setPlaybackMode(_ mode: PlaybackMode) {
        playbackMode = mode
        shownIDs = []
        save()
    }

    private func nextMessage() -> AffirmationMessage? {
        let active = messages.filter { $0.isEnabled }
        guard !active.isEmpty else { return nil }

        var remaining = active.filter { !shownIDs.contains($0.id) }
        if remaining.isEmpty {
            shownIDs = []
            remaining = active
        }

        let message: AffirmationMessage
        switch playbackMode {
        case .sequential:
            message = remaining.first!
        case .shuffled:
            message = remaining.randomElement()!
        }
        shownIDs.insert(message.id)
        return message
    }

    func setTrigger(_ t: AffirmationTrigger) {
        trigger = t
        save()
        guard isEnabled else { return }
        if t == .onWake {
            stopTimer()
        } else {
            startTimer()
        }
    }

    func setInterval(_ minutes: Int) {
        intervalMinutes = minutes
        save()
        if isEnabled {
            startTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        switch scheduleMode {
        case .interval:
            let interval = TimeInterval(intervalMinutes * 60)
            scheduledTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.fireAffirmation()
            }
        case .clockAligned:
            scheduleNextAlignedFire()
        }
    }

    private func stopTimer() {
        scheduledTimer?.invalidate()
        scheduledTimer = nil
    }

    private func scheduleNextAlignedFire() {
        let delay = max(1, nextAlignedDate().timeIntervalSinceNow)
        scheduledTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.fireAffirmation()
            guard self?.scheduleMode == .clockAligned, self?.isEnabled == true else { return }
            self?.scheduleNextAlignedFire()
        }
    }

    private func nextAlignedDate() -> Date {
        let cal = Calendar.current
        let now = Date()
        let midnight = cal.startOfDay(for: now)
        let intervalSeconds = TimeInterval(intervalMinutes * 60)
        let secondsSinceMidnight = now.timeIntervalSince(midnight)
        let nextCount = floor(secondsSinceMidnight / intervalSeconds) + 1
        return midnight.addingTimeInterval(nextCount * intervalSeconds)
    }

    func fireAffirmation() {
        guard isScreenAwake, trigger != .onWake else { return }
        guard let message = nextMessage() else { return }
        Task { @MainActor in
            self.showPopup(text: message.text)
        }
    }

    // MARK: - Screen observers

    private func setupScreenObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc private func screenDidSleep() {
        isScreenAwake = false
    }

    @objc private func screenDidWake() {
        isScreenAwake = true
        guard isEnabled, trigger != .onTimer else { return }
        guard let message = nextMessage() else { return }
        Task { @MainActor in
            self.showPopup(text: message.text)
        }
    }

    // MARK: - Popup

    @MainActor
    func showPopup(text: String) {
        dismissPopup()

        let screens = screensForTarget()
        guard !screens.isEmpty else { return }

        for screen in screens {
            let panel = makePanel(text: text)
            positionPanel(panel, on: screen)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            popupWindows.append(panel)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismissPopup() }
        }
    }

    private func screensForTarget() -> [NSScreen] {
        let all = NSScreen.screens
        guard !all.isEmpty else { return [] }
        switch displayTarget {
        case .main:
            return [NSScreen.main ?? all[0]]
        case .secondary:
            let nonMain = all.filter { $0 != NSScreen.main }
            return [nonMain.first ?? all[0]]
        case .all:
            return all
        }
    }

    @MainActor
    private func makePanel(text: String) -> NSPanel {
        let view = AffirmationPopupView(text: text) { [weak self] in
            Task { @MainActor in self?.dismissPopup() }
        }
        let hosting = NSHostingController(rootView: view)
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting.view
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        return panel
    }

    @MainActor
    private func positionPanel(_ window: NSWindow, on screen: NSScreen) {
        let rect = screen.visibleFrame
        let size = window.frame.size
        let margin: CGFloat = 20
        window.setFrameOrigin(NSPoint(x: rect.maxX - size.width - margin, y: rect.minY + margin))
    }

    @MainActor
    private func dismissPopup() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        let panels = popupWindows
        popupWindows = []
        for panel in panels {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.close() })
        }
    }
}

// MARK: - Popup View

struct AffirmationPopupView: View {
    let text: String
    let onClose: () -> Void

    @State private var progress: Double = 1.0
    @State private var progressTimer: Timer?

    private let duration: TimeInterval = 8

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("✨")
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 4) {
                Text("Afirmação")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)

                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 300)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.1, green: 0.08, blue: 0.18).opacity(0.97))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .overlay(
            VStack {
                Spacer()
                GeometryReader { geo in
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * max(0, progress), height: 2)
                        .animation(.linear(duration: 0.1), value: progress)
                }
                .frame(height: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .onAppear { startProgress() }
        .onDisappear { progressTimer?.invalidate() }
    }

    private func startProgress() {
        let step = 0.1
        let decrement = step / duration
        progressTimer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { _ in
            if progress > 0 {
                progress = max(0, progress - decrement)
            } else {
                progressTimer?.invalidate()
            }
        }
    }
}
