import Foundation
import Observation
import Network
import Security

/// Where the bridge is and the token that opens it (token in the Keychain).
@MainActor @Observable
final class ConnectionSettings {
    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    var token: String {
        didSet { keychainError = Keychain.set(token, account: "bridgeToken") ? nil : "Couldn\u{2019}t save the token to the Keychain" }
    }
    /// Set when the token could not be stored (the connection would be lost after a relaunch).
    var keychainError: String?

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

    /// The server address without a trailing `/linkup` (people paste either form); every bridge path is added to this.
    var rootURL: URL? {
        guard let base = baseURL else { return nil }
        var s = base.absoluteString
        if s.lowercased().hasSuffix("/linkup") { s.removeLast("/linkup".count) }
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
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                    kSecAttrService as String: "com.knightabdo.linkup"]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return true }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                    kSecAttrService as String: "com.knightabdo.linkup", kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
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

/// The one WebSocket to the bridge: reconnects by itself (jittered backoff, network changes, failed pings), resumes
/// every live session from its last event, and pairs replies to requests with `rid`.
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
    @ObservationIgnored private var timers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    /// The generation a reconnect is already scheduled for (scheduling is idempotent per connection attempt).
    @ObservationIgnored private var reconnectGeneration = -1
    @ObservationIgnored private var retryDelay: Double = 0.5
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var lastInterface: NWInterface.InterfaceType?
    @ObservationIgnored private var lastSatisfied = false
    /// The token the bridge answered 401 to: no automatic retries with it.
    @ObservationIgnored private var rejectedToken: String?

    init(settings: ConnectionSettings) { self.settings = settings }

    /// Absolute URL (with the token) for a bridge-relative path such as an artifact or image.
    func resolve(_ relative: String) -> URL? {
        if relative.hasPrefix("http") { return URL(string: relative) }
        guard let root = settings.rootURL else { return nil }
        let path = relative.hasPrefix("/") ? relative : "/" + relative
        let sep = path.contains("?") ? "&" : "?"
        let token = settings.token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: root.absoluteString + path + sep + "token=" + token)
    }

    // MARK: Connection

    /// True after a manual `disconnect()`, false after `connect()`.
    private(set) var userDisconnected = false

    func connect() {
        userDisconnected = false
        guard DebugLaunch.screen == nil else { return }       // screenshot fixtures: never dial out
        guard settings.isConfigured, let root = settings.rootURL else {
            state = .notConfigured
            return
        }
        generation += 1
        let gen = generation
        failPending("Reconnecting")
        pingTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        var comps = URLComponents(url: root.appendingPathComponent("linkup/ws"), resolvingAgainstBaseURL: false)
        comps?.scheme = root.scheme == "http" ? "ws" : "wss"
        comps?.queryItems = [URLQueryItem(name: "token", value: settings.token)]
        guard let url = comps?.url else { state = .offline("Invalid server address"); return }
        state = .connecting
        startMonitor()
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 15
        let ws = session.webSocketTask(with: urlRequest)
        ws.maximumMessageSize = 64 << 20
        task = ws
        ws.resume()
        receive(ws, gen)
        Task { [weak self] in
            guard let self else { return }
            do {
                // The hello replays everything we missed, so it may take long on a slow link.
                let hello = try await self.request("hello", ["since": .object(self.store?.resumePoints() ?? [:])], timeout: 90)
                guard gen == self.generation else { return }
                self.state = .connected
                self.retryDelay = 0.5
                self.rejectedToken = nil
                self.serverName = hello["server"]?["name"]?.string
                self.store?.ingestHello(hello)
                self.startPing(gen)
                await self.store?.refreshCatalog()
            } catch {
                if gen == self.generation { self.scheduleReconnect("Can\u{2019}t reach your PC") }
            }
        }
    }

    func disconnect() {
        userDisconnected = true
        generation += 1
        failPending("Disconnected")
        pingTask?.cancel()
        pingTask = nil
        monitor?.cancel()
        monitor = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        latencyMs = nil
        state = settings.isConfigured ? .offline("Disconnected") : .notConfigured
    }

    /// Called when the app becomes active or the network changes. A connection iOS killed while the app was
    /// suspended still reads "connected", so it is probed with a ping.
    func reconnectIfNeeded() {
        if userDisconnected { return }
        switch state {
        case .connecting:
            return
        case .connected:
            let gen = generation
            Task { [weak self] in await self?.pingOnce(gen, timeout: 4) }
        case .notConfigured:
            connect()
        case .offline:
            if let rejected = rejectedToken, rejected == settings.token { return }   // needs a new pairing, not a retry
            connect()
        }
    }

    /// Reconnects if needed and waits (up to `timeout` seconds) for the hello. For actions from a notification.
    func waitUntilConnected(timeout: TimeInterval = 15) async -> Bool {
        if state == .connected { return true }
        reconnectIfNeeded()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if state == .connected { return true }
            if let rejected = rejectedToken, rejected == settings.token { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return state == .connected
    }

    private func scheduleReconnect(_ why: String) {
        guard reconnectGeneration != generation else { return }
        reconnectGeneration = generation
        failPending(why)
        pingTask?.cancel()
        pingTask = nil
        latencyMs = nil
        task?.cancel(with: .goingAway, reason: nil)
        state = .offline(why)
        let gen = generation
        let delay = retryDelay * Double.random(in: 0.75...1.25)
        retryDelay = min(retryDelay * 2, 15)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, gen == self.generation else { return }
            self.connect()
        }
    }

    /// The bridge refused the token: retrying with it can never work.
    private func tokenRejected() {
        generation += 1
        failPending("Token rejected")
        pingTask?.cancel()
        pingTask = nil
        latencyMs = nil
        task?.cancel(with: .goingAway, reason: nil)
        rejectedToken = settings.token
        state = .offline("Token rejected. Pair again in Settings.")
    }

    // MARK: Receiving

    private func receive(_ ws: URLSessionWebSocketTask, _ gen: Int) {
        ws.receive { [weak self] result in
            // Decoding happens here, on the URLSession queue, not on the main actor.
            switch result {
            case .failure:
                let status = (ws.response as? HTTPURLResponse)?.statusCode
                Task { @MainActor in
                    guard let self, gen == self.generation else { return }
                    if status == 401 || status == 403 { self.tokenRejected() } else { self.scheduleReconnect("Can\u{2019}t reach your PC") }
                }
            case .success(let message):
                let json = Self.decodeFrame(message)
                Task { @MainActor in
                    guard let self, gen == self.generation else { return }
                    if let json { self.dispatch(json) }
                    self.receive(ws, gen)
                }
            }
        }
    }

    nonisolated private static func decodeFrame(_ message: URLSessionWebSocketTask.Message) -> [String: JSONValue]? {
        let data: Data
        switch message {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: return nil
        }
        return try? JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    private func startPing(_ gen: Int) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled, gen == self.generation else { return }
                await self.pingOnce(gen, timeout: 8)
            }
        }
    }

    /// A ping that gets no answer means the link is dead even though the socket looks open: reconnect.
    private func pingOnce(_ gen: Int, timeout: TimeInterval) async {
        let start = Date()
        do {
            try await request("ping", [:], timeout: timeout)
            if gen == generation { latencyMs = Int(Date().timeIntervalSince(start) * 1000) }
        } catch {
            if gen == generation, state == .connected { scheduleReconnect("Connection lost") }
        }
    }

    private func dispatch(_ json: [String: JSONValue]) {
        if let rid = json["rid"]?.string, let waiter = pending.removeValue(forKey: rid) {
            timers.removeValue(forKey: rid)?.cancel()
            if json["op"]?.string == "error" {
                waiter.resume(throwing: BridgeError(message: json["message"]?.string ?? "Bridge error"))
            } else {
                waiter.resume(returning: json)
            }
            return
        }
        store?.ingest(json)
    }

    private func failPending(_ why: String) {
        let waiters = pending
        pending = [:]
        for (_, t) in timers { t.cancel() }
        timers = [:]
        for (_, c) in waiters { c.resume(throwing: BridgeError(message: why)) }
    }

    // MARK: Network changes

    private func startMonitor() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let interface = path.availableInterfaces.first?.type
            Task { @MainActor in self?.pathChanged(satisfied: satisfied, interface: interface) }
        }
        m.start(queue: DispatchQueue(label: "linkup.path", qos: .utility))
        monitor = m
    }

    private func pathChanged(satisfied: Bool, interface: NWInterface.InterfaceType?) {
        let wasSatisfied = lastSatisfied
        let previous = lastInterface
        lastSatisfied = satisfied
        lastInterface = interface
        guard satisfied else { return }
        let switched = previous != nil && interface != previous
        if switched, state == .connected || state == .connecting {
            // Wi-Fi <-> cellular: the old socket is dead even if it doesn't know yet.
            retryDelay = 0.5
            connect()
        } else if !wasSatisfied || state != .connected {
            retryDelay = 0.5
            reconnectIfNeeded()
        }
    }

    // MARK: Requests

    /// Sends an op and waits for its reply. `timeout` defaults to 30 s (90 s for the slow history/catalog ops).
    @discardableResult
    func request(_ op: String, _ params: [String: JSONValue] = [:], timeout: TimeInterval? = nil) async throws -> [String: JSONValue] {
        guard let task, state == .connected || state == .connecting else { throw BridgeError(message: "Not connected to your PC") }
        let rid = UUID().uuidString
        var body = params
        body["op"] = .string(op)
        body["rid"] = .string(rid)
        let data = try JSONEncoder().encode(body)
        let limit = timeout ?? (op == "history" || op == "catalog" ? 90 : 30)
        return try await withCheckedThrowingContinuation { continuation in
            pending[rid] = continuation
            timers[rid] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(limit))
                guard !Task.isCancelled, let self else { return }
                self.timers[rid] = nil
                if let waiter = self.pending.removeValue(forKey: rid) {
                    waiter.resume(throwing: BridgeError(message: "Your PC didn\u{2019}t answer in time"))
                }
            }
            task.send(.string(String(decoding: data, as: UTF8.self))) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in
                    self?.timers.removeValue(forKey: rid)?.cancel()
                    if let waiter = self?.pending.removeValue(forKey: rid) { waiter.resume(throwing: error) }
                }
            }
        }
    }

    /// Fire-and-forget op (send, interrupt, permission…): replies arrive as events. Returns false when there is no
    /// connection to hand it to, so the caller can tell the user instead of losing it silently.
    @discardableResult
    func post(_ op: String, _ params: [String: JSONValue] = [:]) -> Bool {
        guard let task, state == .connected || state == .connecting else { return false }
        var body = params
        body["op"] = .string(op)
        guard let data = try? JSONEncoder().encode(body) else { return false }
        task.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
        return true
    }

    /// Uploads a file to the PC (for attachments); returns the bridge's path/url record.
    func upload(data: Data, name: String, mime: String) async throws -> [String: JSONValue] {
        guard let root = settings.rootURL else { throw BridgeError(message: "Not connected to your PC") }
        var comps = URLComponents(url: root.appendingPathComponent("linkup/upload"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = comps?.url else { throw BridgeError(message: "Invalid server address") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180          // photos and videos over cellular
        request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        let (body, response) = try await URLSession.shared.upload(for: request, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 401 || status == 403 { throw BridgeError(message: "Upload refused: token rejected. Pair again in Settings.") }
            let detail = String(decoding: body.prefix(200), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw BridgeError(message: "Upload failed (\(status))" + (detail.isEmpty ? "" : ": \(detail)"))
        }
        do {
            return try JSONDecoder().decode([String: JSONValue].self, from: body)
        } catch {
            throw BridgeError(message: "Your PC sent an unreadable upload reply")
        }
    }
}
