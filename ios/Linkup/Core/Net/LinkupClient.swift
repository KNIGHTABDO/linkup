import Foundation
import Observation
import Security

/// Where the bridge is and the token that opens it (token in the Keychain).
@MainActor @Observable
final class ConnectionSettings {
    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    var token: String {
        didSet { Keychain.set(token, account: "bridgeToken") }
    }

    init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        token = Keychain.get(account: "bridgeToken") ?? ""
    }

    var isConfigured: Bool { baseURL != nil && !token.isEmpty }

    var baseURL: URL? {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    /// `linkup://pair?url=…&token=…` (printed by `python -m linkup_bridge pair` as a QR code).
    @discardableResult
    func apply(pairingLink url: URL) -> Bool {
        guard url.scheme == "linkup", let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let server = comps.queryItems?.first(where: { $0.name == "url" })?.value,
              let token = comps.queryItems?.first(where: { $0.name == "token" })?.value else { return false }
        serverURL = server
        self.token = token
        return true
    }
}

enum Keychain {
    static func set(_ value: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                    kSecAttrService as String: "com.knightabdo.linkup"]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                    kSecAttrService as String: "com.knightabdo.linkup", kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum ConnectionState: Equatable {
    case notConfigured, connecting, connected, offline(String)

    var label: String {
        switch self {
        case .notConfigured: "Not connected"
        case .connecting: "Connecting\u{2026}"
        case .connected: "Connected"
        case .offline(let why): why
        }
    }
}

struct BridgeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The one WebSocket to the bridge: reconnects by itself (backoff + network changes), resumes every open session
/// from its last event, and pairs replies to requests with `rid`.
@MainActor @Observable
final class LinkupClient {
    let settings: ConnectionSettings
    private(set) var state: ConnectionState = .notConfigured
    private(set) var serverName: String?
    private(set) var latencyMs: Int?

    @ObservationIgnored weak var store: SessionStore?
    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private var session = URLSession(configuration: .default)
    @ObservationIgnored private var pending: [String: CheckedContinuation<[String: JSONValue], Error>] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var retryDelay: Double = 0.5
    @ObservationIgnored private var pingTask: Task<Void, Never>?

    init(settings: ConnectionSettings) { self.settings = settings }

    /// Absolute URL (with the token) for a bridge-relative path such as an artifact or image.
    func resolve(_ relative: String) -> URL? {
        if relative.hasPrefix("http") { return URL(string: relative) }
        guard let base = settings.baseURL else { return nil }
        let sep = relative.contains("?") ? "&" : "?"
        let token = settings.token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: base.absoluteString + relative + sep + "token=" + token)
    }

    // MARK: Connection

    func connect() {
        guard DebugLaunch.screen == nil else { return }       // screenshot fixtures: never dial out
        guard settings.isConfigured, let base = settings.baseURL else {
            state = .notConfigured
            return
        }
        generation += 1
        let gen = generation
        task?.cancel(with: .goingAway, reason: nil)
        var comps = URLComponents(url: base.appendingPathComponent("linkup/ws"), resolvingAgainstBaseURL: false)
        comps?.scheme = base.scheme == "http" ? "ws" : "wss"
        comps?.queryItems = [URLQueryItem(name: "token", value: settings.token)]
        guard let url = comps?.url else { state = .offline("Invalid server address"); return }
        state = .connecting
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 15
        let ws = session.webSocketTask(with: urlRequest)
        ws.maximumMessageSize = 64 << 20
        task = ws
        ws.resume()
        receive(ws, gen)
        Task {
            do {
                let hello = try await request("hello", ["since": .object(store?.resumePoints() ?? [:])])
                guard gen == generation else { return }
                state = .connected
                retryDelay = 0.5
                serverName = hello["server"]?["name"]?.string
                store?.ingestHello(hello)
                startPing(gen)
                await store?.refreshCatalog()
            } catch {
                if gen == generation { scheduleReconnect("Can\u{2019}t reach your PC") }
            }
        }
    }

    func disconnect() {
        generation += 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = settings.isConfigured ? .offline("Disconnected") : .notConfigured
    }

    /// Called when the app becomes active or the network changes.
    func reconnectIfNeeded() {
        switch state {
        case .connected, .connecting: return
        default: connect()
        }
    }

    private func scheduleReconnect(_ why: String) {
        for (_, c) in pending { c.resume(throwing: BridgeError(message: why)) }
        pending = [:]
        state = .offline(why)
        let gen = generation
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 10)
        Task {
            try? await Task.sleep(for: .seconds(delay))
            if gen == generation { connect() }
        }
    }

    private func receive(_ ws: URLSessionWebSocketTask, _ gen: Int) {
        ws.receive { [weak self] result in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                switch result {
                case .failure:
                    self.scheduleReconnect("Can\u{2019}t reach your PC")
                case .success(let message):
                    let data: Data?
                    switch message {
                    case .string(let s): data = Data(s.utf8)
                    case .data(let d): data = d
                    @unknown default: data = nil
                    }
                    if let data, let json = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
                        self.dispatch(json)
                    }
                    self.receive(ws, gen)
                }
            }
        }
    }

    private func startPing(_ gen: Int) {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled, gen == generation {
                let start = Date()
                if (try? await request("ping", [:])) != nil { latencyMs = Int(Date().timeIntervalSince(start) * 1000) }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func dispatch(_ json: [String: JSONValue]) {
        if let rid = json["rid"]?.string, let waiter = pending.removeValue(forKey: rid) {
            if json["op"]?.string == "error" {
                waiter.resume(throwing: BridgeError(message: json["message"]?.string ?? "Bridge error"))
            } else {
                waiter.resume(returning: json)
            }
            return
        }
        store?.ingest(json)
    }

    // MARK: Requests

    /// Sends an op and waits for its reply.
    @discardableResult
    func request(_ op: String, _ params: [String: JSONValue] = [:]) async throws -> [String: JSONValue] {
        guard let task else { throw BridgeError(message: "Not connected to your PC") }
        let rid = UUID().uuidString
        var body = params
        body["op"] = .string(op)
        body["rid"] = .string(rid)
        let data = try JSONEncoder().encode(body)
        return try await withCheckedThrowingContinuation { continuation in
            pending[rid] = continuation
            task.send(.string(String(decoding: data, as: UTF8.self))) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in
                    if let waiter = self?.pending.removeValue(forKey: rid) { waiter.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(op == "history" || op == "catalog" ? 90 : 30))
                if let waiter = pending.removeValue(forKey: rid) {
                    waiter.resume(throwing: BridgeError(message: "Your PC didn\u{2019}t answer in time"))
                }
            }
        }
    }

    /// Fire-and-forget op (send, interrupt, permission…): replies arrive as events.
    func post(_ op: String, _ params: [String: JSONValue] = [:]) {
        guard let task else { return }
        var body = params
        body["op"] = .string(op)
        guard let data = try? JSONEncoder().encode(body) else { return }
        task.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
    }

    /// Uploads a file to the PC (for attachments); returns the bridge's path/url record.
    func upload(data: Data, name: String, mime: String) async throws -> [String: JSONValue] {
        guard let base = settings.baseURL else { throw BridgeError(message: "Not connected to your PC") }
        var comps = URLComponents(url: base.appendingPathComponent("linkup/upload"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = comps?.url else { throw BridgeError(message: "Invalid server address") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        let (body, response) = try await URLSession.shared.upload(for: request, from: data)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BridgeError(message: "Upload failed") }
        return try JSONDecoder().decode([String: JSONValue].self, from: body)
    }
}
