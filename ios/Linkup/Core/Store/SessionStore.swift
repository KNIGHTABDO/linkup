import Foundation
import Observation

/// Everything the UI shows: sessions, their transcripts, the agents' live catalogs and usage.
/// Offline-first: transcripts are cached on disk (one JSON-lines file of events per session) and the bridge only
/// sends what is new since the last event we have.
@MainActor @Observable
final class SessionStore {
    let client: LinkupClient
    private(set) var sessions: [SessionInfo] = []
    private(set) var agents: [AgentInfo] = []
    private(set) var usage: UsageSnapshot?
    private(set) var projects: [ProjectInfo] = []
    private(set) var lastError: String?
    @ObservationIgnored private var transcripts: [String: Transcript] = [:]
    @ObservationIgnored private let cache = EventCache()

    init(client: LinkupClient) {
        self.client = client
        sessions = cache.loadSessions()
        client.store = self
    }

    // MARK: Lookups

    func transcript(for sessionId: String) -> Transcript {
        if let t = transcripts[sessionId] { return t }
        let t = Transcript(sessionId: sessionId)
        for e in cache.loadEvents(sessionId) { t.apply(e) }
        transcripts[sessionId] = t
        return t
    }

    func session(_ id: String) -> SessionInfo? { sessions.first { $0.id == id } }
    func agent(_ id: String?) -> AgentInfo? { agents.first { $0.id == id } }

    /// Last event we hold for every session the user has opened (the bridge replays the rest on reconnect).
    func resumePoints() -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (id, t) in transcripts { out[id] = .number(Double(t.lastSeq)) }
        return out
    }

    func clearError() { lastError = nil }

    // MARK: Incoming

    func ingestHello(_ json: [String: JSONValue]) {
        if let list = json["sessions"] { setSessions(decode([SessionInfo].self, list) ?? sessions) }
        if let u = json["usage"] { usage = decode(UsageSnapshot.self, u) ?? usage }
    }

    func ingest(_ json: [String: JSONValue]) {
        switch json["op"]?.string {
        case "event":
            guard let sid = json["session"]?.string, let raw = json["event"]?.object else { return }
            let event = BridgeEvent(json: raw)
            cache.append(raw, to: sid)
            transcripts[sid]?.apply(event)
        case "session":
            if let s = json["session"].flatMap({ decode(SessionInfo.self, $0) }) { upsert(s) }
        case "sessions":
            if let list = json["sessions"] { setSessions(decode([SessionInfo].self, list) ?? sessions) }
        case "deleted":
            if let sid = json["session"]?.string { removeLocal(sid) }
        case "usage":
            if let u = json["usage"] { usage = decode(UsageSnapshot.self, u) ?? usage }
        case "catalog":
            applyCatalog(json)
        case "error":
            lastError = json["message"]?.string
        default:
            break
        }
    }

    private func applyCatalog(_ json: [String: JSONValue]) {
        if let list = json["agents"], let decoded = decode([AgentInfo].self, list) { agents = decoded }
        if let u = json["usage"] { usage = decode(UsageSnapshot.self, u) ?? usage }
    }

    private func upsert(_ s: SessionInfo) {
        var list = sessions
        if let i = list.firstIndex(where: { $0.id == s.id }) { list[i] = s } else { list.append(s) }
        setSessions(list)
    }

    private func setSessions(_ list: [SessionInfo]) {
        sessions = list.sorted { ($0.pinned ? 1 : 0, $0.updated) > ($1.pinned ? 1 : 0, $1.updated) }
        cache.saveSessions(sessions)
    }

    private func removeLocal(_ sid: String) {
        sessions.removeAll { $0.id == sid }
        transcripts[sid] = nil
        cache.deleteEvents(sid)
        cache.saveSessions(sessions)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ value: JSONValue) -> T? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: Actions

    func refreshCatalog(force: Bool = false) async {
        do {
            let json = try await client.request("catalog", ["force": .bool(force)])
            applyCatalog(json)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadProjects() async {
        guard let json = try? await client.request("projects"),
              let list = json["projects"].flatMap({ decode([ProjectInfo].self, $0) }) else { return }
        projects = list
    }

    func loadHistory() async throws -> [HistoryItem] {
        let json = try await client.request("history")
        return json["sessions"].flatMap { decode([HistoryItem].self, $0) } ?? []
    }

    /// Opens a session's live stream (and catches up from the cached transcript).
    func open(_ sessionId: String) {
        let t = transcript(for: sessionId)
        client.post("subscribe", ["session": .string(sessionId), "since": .number(Double(t.lastSeq))])
        if session(sessionId)?.hasUnread == true { client.post("read", ["session": .string(sessionId)]) }
    }

    func create(agent: String, model: String?, effort: String?, cwd: String?, permissionMode: String? = nil) async throws -> SessionInfo {
        var params: [String: JSONValue] = ["agent": .string(agent)]
        if let model { params["model"] = .string(model) }
        if let effort { params["effort"] = .string(effort) }
        if let cwd { params["cwd"] = .string(cwd) }
        if let permissionMode { params["permissionMode"] = .string(permissionMode) }
        let json = try await client.request("create", params)
        guard let s = json["session"].flatMap({ decode(SessionInfo.self, $0) }) else {
            throw BridgeError(message: "Your PC couldn\u{2019}t start the session")
        }
        upsert(s)
        _ = transcript(for: s.id)
        return s
    }

    func importHistory(_ item: HistoryItem) async throws -> SessionInfo {
        let json = try await client.request("import", ["nativeId": .string(item.nativeId)])
        guard let s = json["session"].flatMap({ decode(SessionInfo.self, $0) }) else {
            throw BridgeError(message: "Couldn\u{2019}t open that session")
        }
        upsert(s)
        open(s.id)
        return s
    }

    /// attachments: records returned by `LinkupClient.upload` ({path, name, mime}).
    func send(_ text: String, to sessionId: String, attachments: [[String: JSONValue]] = []) {
        client.post("send", ["session": .string(sessionId), "text": .string(text), "attachments": .array(attachments.map { .object($0) })])
    }

    func interrupt(_ sessionId: String) { client.post("interrupt", ["session": .string(sessionId)]) }

    func answer(_ request: PermissionRequest, in sessionId: String, allow: Bool) {
        request.allowed = allow
        client.post("permission", ["session": .string(sessionId), "id": .string(request.id), "allow": .bool(allow)])
    }

    func update(_ sessionId: String, title: String? = nil, pinned: Bool? = nil, model: String? = nil,
                effort: String? = nil, permissionMode: String? = nil) {
        var params: [String: JSONValue] = ["session": .string(sessionId)]
        if let title { params["title"] = .string(title) }
        if let pinned { params["pinned"] = .bool(pinned) }
        if let model { params["model"] = .string(model) }
        if let effort { params["effort"] = .string(effort) }
        if let permissionMode { params["permissionMode"] = .string(permissionMode) }
        client.post("update", params)
    }

    func delete(_ sessionId: String) {
        client.post("delete", ["session": .string(sessionId)])
        removeLocal(sessionId)
    }
}

/// Disk cache: sessions.json + events/<session>.jsonl (raw bridge events).
final class EventCache {
    private let root: URL
    private let queue = DispatchQueue(label: "linkup.cache", qos: .utility)

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("Linkup", isDirectory: true)
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("events"), withIntermediateDirectories: true)
    }

    private func file(_ sid: String) -> URL { root.appendingPathComponent("events/\(sid).jsonl") }

    func loadSessions() -> [SessionInfo] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("sessions.json")) else { return [] }
        return (try? JSONDecoder().decode([SessionInfo].self, from: data)) ?? []
    }

    func saveSessions(_ sessions: [SessionInfo]) {
        let url = root.appendingPathComponent("sessions.json")
        queue.async {
            if let data = try? JSONEncoder().encode(sessions) { try? data.write(to: url, options: .atomic) }
        }
    }

    func loadEvents(_ sid: String) -> [BridgeEvent] {
        guard let text = try? String(contentsOf: file(sid), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            (try? JSONDecoder().decode([String: JSONValue].self, from: Data(line.utf8))).map(BridgeEvent.init)
        }
    }

    func append(_ raw: [String: JSONValue], to sid: String) {
        let url = file(sid)
        queue.async {
            guard var data = try? JSONEncoder().encode(raw) else { return }
            data.append(0x0A)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    func deleteEvents(_ sid: String) {
        let url = file(sid)
        queue.async { try? FileManager.default.removeItem(at: url) }
    }
}
