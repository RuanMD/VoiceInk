import SwiftUI

enum IntervalUnit: String, CaseIterable {
    case minutes = "Minutos"
    case hours = "Horas"
    case days = "Dias"

    func toMinutes(_ value: Int) -> Int {
        switch self {
        case .minutes: return max(1, value)
        case .hours:   return max(1, value) * 60
        case .days:    return max(1, value) * 1440
        }
    }

    static func from(minutes: Int) -> (value: Int, unit: IntervalUnit) {
        if minutes % 1440 == 0 { return (minutes / 1440, .days) }
        if minutes % 60 == 0   { return (minutes / 60, .hours) }
        return (minutes, .minutes)
    }
}

struct AffirmationsView: View {
    @ObservedObject private var manager = AffirmationManager.shared
    @State private var newMessageText = ""
    @State private var editingMessage: AffirmationMessage? = nil
    @State private var editText = ""
    @FocusState private var isInputFocused: Bool
    @FocusState private var isIntervalFocused: Bool
    @State private var intervalValueText: String = "1"
    @State private var intervalUnit: IntervalUnit = .hours

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                enableSection
                displaySection
                triggerSection
                if manager.trigger != .onWake {
                    intervalSection
                }
                playbackSection
                messagesSection
            }
            .padding(24)
        }
        .onAppear {
            let parsed = IntervalUnit.from(minutes: manager.intervalMinutes)
            intervalValueText = "\(parsed.value)"
            intervalUnit = parsed.unit
        }
        .sheet(item: $editingMessage) { msg in
            EditAffirmationSheet(text: editText) { newText in
                manager.updateMessage(msg, newText: newText)
                editingMessage = nil
            } onCancel: {
                editingMessage = nil
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("✨")
                .font(.system(size: 40))
            Text("Afirmações")
                .font(.system(size: 22, weight: .bold))
            Text("Receba lembretes motivacionais enquanto trabalha")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var enableSection: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ativar afirmações")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Exibe pop-ups com suas mensagens em intervalos regulares")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { manager.isEnabled },
                    set: { manager.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(4)
        }
    }

    private var displaySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "display.2")
                        .foregroundColor(.purple)
                    Text("Monitor")
                        .font(.system(size: 14, weight: .semibold))
                }

                HStack(spacing: 10) {
                    ForEach(DisplayTarget.allCases, id: \.self) { option in
                        Button(action: { manager.setDisplayTarget(option) }) {
                            VStack(spacing: 6) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 16))
                                Text(option.label)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(manager.displayTarget == option
                                ? Color.purple.opacity(0.18)
                                : Color.secondary.opacity(0.07))
                            .foregroundColor(manager.displayTarget == option ? .purple : .secondary)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(manager.displayTarget == option
                                        ? Color.purple.opacity(0.5)
                                        : Color.clear,
                                        lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(4)
        }
        .opacity(manager.isEnabled ? 1 : 0.5)
        .disabled(!manager.isEnabled)
    }

    private var triggerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.purple)
                    Text("Quando exibir o pop-up")
                        .font(.system(size: 14, weight: .semibold))
                }

                HStack(spacing: 10) {
                    ForEach(AffirmationTrigger.allCases, id: \.self) { option in
                        Button(action: { manager.setTrigger(option) }) {
                            VStack(spacing: 6) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 16))
                                Text(option.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(manager.trigger == option
                                ? Color.purple.opacity(0.18)
                                : Color.secondary.opacity(0.07))
                            .foregroundColor(manager.trigger == option ? .purple : .secondary)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(manager.trigger == option
                                        ? Color.purple.opacity(0.5)
                                        : Color.clear,
                                        lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(4)
        }
        .opacity(manager.isEnabled ? 1 : 0.5)
        .disabled(!manager.isEnabled)
    }

    private var intervalSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.purple)
                    Text("Intervalo entre mensagens")
                        .font(.system(size: 14, weight: .semibold))
                }

                HStack(spacing: 10) {
                    TextField("", text: $intervalValueText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .frame(width: 70)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .focused($isIntervalFocused)
                        .onSubmit { applyInterval() }
                        .onChange(of: intervalValueText) { newVal in
                            let filtered = newVal.filter { $0.isNumber }
                            if filtered != newVal { intervalValueText = filtered }
                        }

                    Picker("", selection: $intervalUnit) {
                        ForEach(IntervalUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                    .onChange(of: intervalUnit) { _ in applyInterval() }

                    Button(action: applyInterval) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.purple)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Divider()

                HStack(spacing: 10) {
                    ForEach(ScheduleMode.allCases, id: \.self) { mode in
                        Button(action: { manager.setScheduleMode(mode) }) {
                            HStack(spacing: 6) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 12))
                                Text(mode.label)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(manager.scheduleMode == mode
                                ? Color.purple.opacity(0.18)
                                : Color.secondary.opacity(0.07))
                            .foregroundColor(manager.scheduleMode == mode ? .purple : .secondary)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(manager.scheduleMode == mode
                                        ? Color.purple.opacity(0.5)
                                        : Color.clear,
                                        lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Text(manager.scheduleMode.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(4)
        }
        .opacity(manager.isEnabled ? 1 : 0.5)
        .disabled(!manager.isEnabled)
    }

    private func applyInterval() {
        guard let value = Int(intervalValueText), value > 0 else {
            intervalValueText = "1"
            return
        }
        isIntervalFocused = false
        manager.setInterval(intervalUnit.toMinutes(value))
    }

    private var playbackSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.purple)
                    Text("Ordem de exibição")
                        .font(.system(size: 14, weight: .semibold))
                }

                HStack(spacing: 10) {
                    ForEach(PlaybackMode.allCases, id: \.self) { mode in
                        Button(action: { manager.setPlaybackMode(mode) }) {
                            HStack(spacing: 8) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 14))
                                Text(mode.label)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(manager.playbackMode == mode
                                ? Color.purple.opacity(0.18)
                                : Color.secondary.opacity(0.07))
                            .foregroundColor(manager.playbackMode == mode ? .purple : .secondary)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(manager.playbackMode == mode
                                        ? Color.purple.opacity(0.5)
                                        : Color.clear,
                                        lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Text(manager.playbackMode == .sequential
                    ? "Exibe as mensagens na ordem que foram adicionadas, em loop."
                    : "Exibe todas as mensagens em ordem aleatória antes de repetir qualquer uma.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(4)
        }
        .opacity(manager.isEnabled ? 1 : 0.5)
        .disabled(!manager.isEnabled)
    }

    private var messagesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "text.bubble.fill")
                        .foregroundColor(.purple)
                    Text("Minhas mensagens")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(manager.messages.filter { $0.isEnabled }.count) ativas")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                addMessageField

                if manager.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                previewButton
            }
            .padding(4)
        }
    }

    private var addMessageField: some View {
        HStack(spacing: 8) {
            TextField("Adicionar mensagem de afirmação...", text: $newMessageText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .focused($isInputFocused)
                .onSubmit { addMessage() }

            Button(action: addMessage) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(newMessageText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .purple)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(newMessageText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Nenhuma mensagem ainda")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("Adicione afirmações como \"Eu sou forte\", \"Eu sou capaz\"")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var messageList: some View {
        VStack(spacing: 6) {
            ForEach(manager.messages) { message in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { message.isEnabled },
                        set: { _ in manager.toggleMessage(message) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)

                    Text(message.text)
                        .font(.system(size: 13))
                        .foregroundColor(message.isEnabled ? .primary : .secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: {
                        editText = message.text
                        editingMessage = message
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        if let idx = manager.messages.firstIndex(where: { $0.id == message.id }) {
                            manager.deleteMessage(at: IndexSet(integer: idx))
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    private var previewButton: some View {
        Button(action: {
            let active = manager.messages.filter { $0.isEnabled }
            guard let msg = active.randomElement() else { return }
            Task { @MainActor in
                manager.showPopup(text: msg.text)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill")
                Text("Pré-visualizar pop-up")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.purple)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.purple.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(manager.messages.filter { $0.isEnabled }.isEmpty)
        .opacity(manager.messages.filter { $0.isEnabled }.isEmpty ? 0.5 : 1)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Actions

    private func addMessage() {
        guard !newMessageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        manager.addMessage(newMessageText)
        newMessageText = ""
        isInputFocused = false
    }
}

// MARK: - Edit Sheet

struct EditAffirmationSheet: View {
    @State private var text: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(text: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: text)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Editar mensagem")
                .font(.system(size: 16, weight: .semibold))

            TextField("Mensagem", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))

            HStack {
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Salvar") { onSave(text) }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
