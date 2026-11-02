import Foundation
import Network
import OSLog
import SwiftData

/// Local-only HTTP API to manage the dictionary from other programs (e.g. an AI agent).
///
/// - Listens on 127.0.0.1 only (never reachable from the network).
/// - Every request needs `Authorization: Bearer <token>`; the token lives in
///   `~/Library/Application Support/com.prakashjoshipax.VoiceInk/api-token` (mode 0600).
/// - Requests carrying an `Origin` header (browsers) or a non-local `Host` are rejected.
///
/// Endpoints (JSON):
///   GET  /health                        -> {"ok":true}
///   GET  /dictionary                    -> {"vocabulary":[...],"replacements":[{"original":"a, b","replacement":"c"}]}
///   POST /dictionary/replacements       -> {"original":"x" | ["x","y"], "replacement":"z"}
///   POST /dictionary/vocabulary         -> {"terms":"a, b" | ["a","b"]}
@MainActor
final class DictionaryAPIServer {
    static let defaultPort: UInt16 = 47821
    /// Keeps the server alive for the lifetime of the app.
    static var shared: DictionaryAPIServer?

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DictionaryAPI")
    private let context: ModelContext
    private let port: UInt16
    private let token: String
    private var listener: NWListener?

    init(context: ModelContext, port: UInt16 = DictionaryAPIServer.defaultPort) {
        self.context = context
        self.port = port
        self.token = Self.loadOrCreateToken()
    }

    // MARK: - Lifecycle

    func start() {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.handle(connection) }
            }
            listener.stateUpdateHandler = { [logger] state in
                switch state {
                case .ready: logger.notice("Dictionary API listening on 127.0.0.1")
                case .failed(let error): logger.error("Dictionary API failed: \(error.localizedDescription, privacy: .public)")
                default: break
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            logger.error("Dictionary API could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Token

    private static func tokenURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
            .appendingPathComponent("api-token")
    }

    private static func loadOrCreateToken() -> String {
        let url = tokenURL()
        if let existing = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), existing.count >= 32
        {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? token.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return token
    }

    // MARK: - Connection handling

    private struct Request {
        var method = ""
        var path = ""
        var headers: [String: String] = [:]
        var body = Data()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if error != nil || buffer.count > 1_000_000 {
                    connection.cancel()
                    return
                }
                switch Self.parse(buffer) {
                case .some(let request):
                    let (status, body) = self.route(request)
                    self.send(connection, status: status, json: body)
                case .none:
                    if isComplete { connection.cancel() } else { self.receive(connection, buffer: buffer) }
                }
            }
        }
    }

    /// Returns a request once headers and the full body have arrived.
    private static func parse(_ data: Data) -> Request? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)),
            let head = String(data: data[..<separator.lowerBound], encoding: .utf8)
        else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var request = Request(method: String(requestLine[0]), path: String(requestLine[1]))
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            request.headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(request.headers["content-length"] ?? "0") ?? 0
        let bodyStart = separator.upperBound
        guard data.count - bodyStart >= length else { return nil }
        request.body = data[bodyStart..<(bodyStart + length)]
        return request
    }

    private func send(_ connection: NWConnection, status: Int, json: [String: Any]) {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 409: "Conflict"][status] ?? "Error"
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        var response = Data(
            "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Routing

    private func route(_ request: Request) -> (Int, [String: Any]) {
        // Block browsers and DNS-rebinding: only direct local clients are allowed.
        if request.headers["origin"] != nil { return (403, ["error": "browser requests are not allowed"]) }
        let host = (request.headers["host"] ?? "").lowercased()
        guard host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else {
            return (403, ["error": "invalid host"])
        }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            return (401, ["error": "missing or invalid token"])
        }

        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        switch (request.method, path) {
        case ("GET", "/health"):
            return (200, ["ok": true])
        case ("GET", "/dictionary"):
            return (200, listDictionary())
        case ("POST", "/dictionary/replacements"):
            return addReplacement(request.body)
        case ("POST", "/dictionary/vocabulary"):
            return addVocabulary(request.body)
        default:
            return (404, ["error": "not found"])
        }
    }

    private func jsonObject(_ body: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    /// Accepts "a, b" or ["a","b"] and returns the clean list.
    private func stringList(_ value: Any?) -> [String] {
        let raw: [String]
        if let array = value as? [String] {
            raw = array
        } else if let string = value as? String {
            raw = string.split(separator: ",").map(String.init)
        } else {
            raw = []
        }
        return raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func listDictionary() -> [String: Any] {
        let words = (try? context.fetch(FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)]))) ?? []
        let rules = (try? context.fetch(FetchDescriptor<WordReplacement>(sortBy: [SortDescriptor(\.originalText)]))) ?? []
        return [
            "vocabulary": words.map(\.word),
            "replacements": rules.map { ["original": $0.originalText, "replacement": $0.replacementText] },
        ]
    }

    private func addReplacement(_ body: Data) -> (Int, [String: Any]) {
        guard let object = jsonObject(body) else { return (400, ["error": "invalid JSON"]) }
        let originals = stringList(object["original"])
        let replacement = (object["replacement"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !originals.isEmpty, !replacement.isEmpty else {
            return (400, ["error": "'original' and 'replacement' are required"])
        }
        let existing = (try? context.fetch(FetchDescriptor<WordReplacement>())) ?? []
        if let error = DictionaryService.addWordReplacement(
            original: originals.joined(separator: ", "), replacement: replacement,
            existing: existing, context: context)
        {
            return (409, ["error": error])
        }
        logger.notice("API added replacement (\(originals.count, privacy: .public) variant(s))")
        return (200, ["ok": true, "original": originals, "replacement": replacement])
    }

    private func addVocabulary(_ body: Data) -> (Int, [String: Any]) {
        guard let object = jsonObject(body) else { return (400, ["error": "invalid JSON"]) }
        let terms = stringList(object["terms"])
        guard !terms.isEmpty else { return (400, ["error": "'terms' is required"]) }
        let existing = (try? context.fetch(FetchDescriptor<VocabularyWord>())) ?? []
        if let error = DictionaryService.addVocabularyWords(
            terms.joined(separator: ", "), existing: existing, context: context)
        {
            return (409, ["error": error])
        }
        logger.notice("API added \(terms.count, privacy: .public) vocabulary term(s)")
        return (200, ["ok": true, "terms": terms])
    }
}
