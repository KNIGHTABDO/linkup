import Foundation
import Observation

/// Everything the UI shows: sessions, their transcripts, the agents' live catalogs and usage.
/// Offline-first: transcripts are cached on disk (one JSON-lines file of events per session) and the bridge only
/// sends what is new since the last event we have.
///
/// Transcripts are created on demand, filled from disk off the main actor (`Transcript.isLoading` while that runs;
/// live events that arrive meanwhile are buffered and applied afterwards, deduped by seq) and evicted LRU-style.
/// A session is "live" (subscribed on the bridge) from `open` until `close`/eviction, and always while it runs.
@MainActor @Observable
final class SessionStore {
    let client: LinkupClient
    private(set) var sessions: [SessionInfo] = []
    private(set) var agents: [AgentInfo] = []
    private(set) var usage: UsageSnapshot?
    private(set) var projects: [ProjectInfo] = []
    private(set) var lastError: String?

    /// Set by the app on scene-phase changes: a finished turn only counts as read while the app is in front.
    @ObservationIgnored var isAppActive = true
    /// Called after a message was handed to the bridge (LiveManager starts the keep-alive).
    @ObservationIgnored var didSend: ((String) -> Void)?
    /// The chat on screen.
    @ObservationIgnored private(set) var openSessionId: String?

    @ObservationIgnored private var transcripts: [String: Transcript] = [:]
    /// Least recently used first.
    @ObservationIgnored private var lru: [String] = []
    /// Sessions we want events for. Subscriptions already sent on the current connection are in `sent`.
    @ObservationIgnored private var live: Set<String> = []
    @ObservationIgnored private var sent: Set<String> = []
    @ObservationIgnored private var loadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var buffered: [String: [BridgeEvent]] = [:]
    /// Deleted sessions: late events, pushes and list entries for them are ignored.
    @ObservationIgnored private var tombstones: Set<String> = []
    /// A gap was detected at this seq and the bridge was asked to replay; gap events are dropped until the deadline.
    @ObservationIgnored private var resyncing: [String: (seq: Int, until: Date)] = [:]
    @ObservationIgnored private let cache: EventCache
    @ObservationIgnored private let jsonEncoder = JSONEncoder()
    @ObservationIgnored private let jsonDecoder = JSONDecoder()

    private static let maxTranscripts = 8

    init(client: LinkupClient) {
        self.client = client
        cache = EventCache(writes: DebugLaunch.screen == nil)
        sessions = cache.loadSessions()
        client.store = self
    }

    // MARK: Lookups

    /// Returns at once. A transcript that still reads its cache has `isLoading == true`.
    func transcript(for sessionId: String) -> Transcript {
        if let t = transcripts[sessionId] {
            touch(sessionId)
            return t
        }
        let t = Transcript(sessionId: sessionId)
        transcripts[sessionId] = t
        touch(sessionId)
        let hasCache = session(sessionId).map { $0.lastSeq > 0 } ?? true
        if DebugLaunch.screen == nil, hasCache, !tombstones.contains(sessionId) { startLoad(t) }
        return t
    }

    /// The transcript if something already opened it. Never creates or loads one (LiveManager uses this).
    func existingTranscript(for sessionId: String) -> Transcript? { transcripts[sessionId] }

    func session(_ id: String) -> SessionInfo? { sessions.first { $0.id == id } }
    func agent(_ id: String?) -> AgentInfo? { agents.first { $0.id == id } }

    /// Last event we hold for every live session (the bridge replays the rest on reconnect). Transcripts still
    /// loading are left out: they subscribe themselves when their cache is read.
    func resumePoints() -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for id in live {
            if let t = transcripts[id], !t.isLoading { out[id] = .number(Double(t.lastSeq)) }
        }
        return out
    }

    func clearError() { lastError = nil }

    /// Writes buffered cache appends and the session list to disk (call when the app goes to the background).
    func flushCache() { cache.flush() }

    private func touch(_ sid: String) {
        if lru.last == sid { return }
        lru.removeAll { $0 == sid }
        lru.append(sid)
    }

    // MARK: Loading

    private func startLoad(_ t: Transcript) {
        let sid = t.sessionId
        t.isLoading = true
        let cache = self.cache
        loadTasks[sid] = Task { [weak self] in
            let events = await Task.detached(priority: .userInitiated) { cache.loadEvents(sid) }.value
            guard let self else { return }
            await self.finishLoad(t, events)
        }
    }

    private func finishLoad(_ t: Transcript, _ events: [BridgeEvent]) async {
        let sid = t.sessionId
        var i = 0
        while i < events.count {
            guard !Task.isCancelled, transcripts[sid] === t else { return }
            let end = min(i + 300, events.count)
            for e in events[i..<end] { t.apply(e) }
            i = end
            if i < events.count { await Task.yield() }
        }
        guard transcripts[sid] === t else { return }
        loadTasks[sid] = nil
        for e in buffered.removeValue(forKey: sid) ?? [] { applyLive(e, to: t) }
        t.isLoading = false
        if live.contains(sid) { subscribeIfNeeded(t) }
        evictIfNeeded()
    }

    // MARK: Open / close

    /// Opens a session's live stream (and catches up from the cached transcript). Safe to call repeatedly.
    func open(_ sessionId: String) {
        guard !tombstones.contains(sessionId) else { return }
        openSessionId = sessionId
        let t = transcript(for: sessionId)
        live.insert(sessionId)
        if !t.isLoading { subscribeIfNeeded(t) }
        markRead(sessionId)
        evictIfNeeded()
    }

    /// The user left this chat: stop live updates for it unless it is running (unsubscribe + evict old transcripts).
    func close(_ sessionId: String) {
        if openSessionId == sessionId { openSessionId = nil }
        let running = session(sessionId)?.isRunning == true || transcripts[sessionId]?.isWorking == true
        if !running { unsubscribe(sessionId) }
        evictIfNeeded()
    }

    private func subscribeIfNeeded(_ t: Transcript) {
        let sid = t.sessionId
        guard !sent.contains(sid) else { return }
        if client.post("subscribe", ["session": .string(sid), "since": .number(Double(t.lastSeq))]) { sent.insert(sid) }
    }

    private func unsubscribe(_ sid: String) {
        guard live.remove(sid) != nil else { return }
        if sent.remove(sid) != nil { client.post("unsubscribe", ["session": .string(sid)]) }
    }

    private func evictIfNeeded() {
        guard DebugLaunch.screen == nil, transcripts.count > Self.maxTranscripts else { return }
        for sid in lru {
            guard transcripts.count > Self.maxTranscripts else { break }
            guard sid != openSessionId, let t = transcripts[sid], !t.isLoading, !t.isWorking,
                  session(sid)?.isRunning != true else { continue }
            unsubscribe(sid)
            forget(sid)
        }
    }

    private func forget(_ sid: String) {
        transcripts[sid] = nil
        lru.removeAll { $0 == sid }
        loadTasks[sid]?.cancel()
        loadTasks[sid] = nil
        buffered[sid] = nil
        resyncing[sid] = nil
        live.remove(sid)
        sent.remove(sid)
    }

    // MARK: Incoming

    func ingestHello(_ json: [String: JSONValue]) {
        if let list = json["sessions"], let r = decodeList(SessionInfo.self, list, what: "sessions") {
            setSessions(r.items)
            if r.skipped == 0 {
                // Authoritative list: sessions deleted on another device while we were away are gone for good.
                let ids = Set(r.items.map(\.id))
                for sid in Array(transcripts.keys) where !ids.contains(sid) && !tombstones.contains(sid) { removeLocal(sid) }
                cache.prune(keeping: ids)
            }
        }
        if let u = json["usage"] { usage = decode(UsageSnapshot.self, u) ?? usage }
        // The hello carried a resume point for every live session whose cache had loaded.
        sent = Set(live.filter { transcripts[$0]?.isLoading == false })
        for id in live {
            if let t = transcripts[id], !t.isLoading { subscribeIfNeeded(t) }
        }
        if let id = openSessionId { open(id) }
    }

    func ingest(_ json: [String: JSONValue]) {
        switch json["op"]?.string {
        case "event":
            guard let sid = json["session"]?.string, let raw = json["event"]?.object,
                  !tombstones.contains(sid), let t = transcripts[sid] else { return }
            let event = BridgeEvent(json: raw)
            if t.isLoading {
                buffered[sid, default: []].append(event)
            } else {
                applyLive(event, to: t)
            }
        case "session":
            if let s = json["session"].flatMap({ decode(SessionInfo.self, $0) }) { upsert(s) }
        case "sessions":
            if let list = json["sessions"], let r = decodeList(SessionInfo.self, list, what: "sessions") { setSessions(r.items) }
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

    private func applyLive(_ e: BridgeEvent, to t: Transcript) {
        let sid = t.sessionId
        if t.hasGap(before: e.seq) {
            if let r = resyncing[sid], r.seq == t.lastSeq {
                if Date() < r.until { return }          // the replay is on its way; it will fill the gap in order
            } else {
                resyncing[sid] = (t.lastSeq, Date().addingTimeInterval(4))
                client.post("subscribe", ["session": .string(sid), "since": .number(Double(t.lastSeq))])
                return
            }
        }
        guard t.apply(e) else { return }                 // duplicate (replay): already cached
        cache.append(e.payload, to: sid)
        if e.type == "turn.end", sid == openSessionId, isAppActive { markRead(sid) }
    }

    private func applyCatalog(_ json: [String: JSONValue]) {
        if let list = json["agents"], let r = decodeList(AgentInfo.self, list, what: "agents") { agents = r.items }
        if let u = json["usage"] { usage = decode(UsageSnapshot.self, u) ?? usage }
    }

    private func upsert(_ s: SessionInfo) {
        guard !tombstones.contains(s.id) else { return }
        var list = sessions
        if let i = list.firstIndex(where: { $0.id == s.id }) {
            if list[i] == s { return }
            list[i] = s
        } else {
            list.append(s)
        }
        setSessions(list)
    }

    /// Replaces `sessions` only when something changed (observers re-render on assignment), and saves it debounced.
    private func setSessions(_ incoming: [SessionInfo]) {
        var list = incoming.filter { !tombstones.contains($0.id) }
        list.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.updated != b.updated { return a.updated > b.updated }
            return a.id < b.id
        }
        // The chat in front is read by definition.
        if isAppActive, let id = openSessionId, let i = list.firstIndex(where: { $0.id == id }), list[i].hasUnread {
            list[i].unread = 0
            client.post("read", ["session": .string(id)])
        }
        // A turn we still show as live although the bridge says idle and we hold all its events: end it.
        for s in list where s.status != "running" {
            if let t = transcripts[s.id], !t.isLoading, t.isWorking, t.lastSeq >= s.lastSeq { t.endStaleTurn() }
        }
        guard list != sessions else { return }
        sessions = list
        cache.saveSessions(list)
    }

    private func markRead(_ sid: String) {
        guard let i = sessions.firstIndex(where: { $0.id == sid }), sessions[i].hasUnread else { return }
        sessions[i].unread = 0
        cache.saveSessions(sessions)
        client.post("read", ["session": .string(sid)])
    }

    private func removeLocal(_ sid: String) {
        tombstones.insert(sid)
        forget(sid)
        if openSessionId == sid { openSessionId = nil }
        cache.deleteEvents(sid)
        PinnedStore.shared.removeAll(for: sid)
        let remaining = sessions.filter { $0.id != sid }
        if remaining.count != sessions.count {
            sessions = remaining
            cache.saveSessions(remaining)
        }
    }

    // MARK: Decoding

    private func decode<T: Decodable>(_ type: T.Type, _ value: JSONValue) -> T? {
        guard let data = try? jsonEncoder.encode(value) else { return nil }
        return try? jsonDecoder.decode(type, from: data)
    }

    /// Decodes an array element by element, so one bad row doesn't hide the rest. Surfaces the skipped count.
    private func decodeList<T: Decodable>(_ type: T.Type, _ value: JSONValue, what: String) -> (items: [T], skipped: Int)? {
        guard let array = value.array else { return nil }
        var items: [T] = []
        var skipped = 0
        for element in array {
            if let item = decode(type, element) { items.append(item) } else { skipped += 1 }
        }
        if skipped > 0 { lastError = "Couldn\u{2019}t read \(skipped) of \(array.count) \(what) from your PC. Update the Linkup bridge." }
        return (items, skipped)
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
        do {
            let json = try await client.request("projects")
            if let list = json["projects"], let r = decodeList(ProjectInfo.self, list, what: "projects") { projects = r.items }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadHistory() async throws -> [HistoryItem] {
        let json = try await client.request("history")
        return json["sessions"].flatMap { decodeList(HistoryItem.self, $0, what: "sessions") }?.items ?? []
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
    /// Returns false (and sets `lastError`) when the message could not be handed to the bridge, so the caller keeps the draft.
    @discardableResult
    func send(_ text: String, to sessionId: String, attachments: [[String: JSONValue]] = []) -> Bool {
        let ok = client.post("send", ["session": .string(sessionId), "text": .string(text),
                                      "attachments": .array(attachments.map { .object($0) })])
        guard ok else {
            lastError = "Not connected to your PC. Your message wasn\u{2019}t sent."
            return false
        }
        // Whatever the agent does next must reach us, even if this chat was never opened.
        let t = transcript(for: sessionId)
        live.insert(sessionId)
        if !t.isLoading { subscribeIfNeeded(t) }
        didSend?(sessionId)
        return true
    }

    @discardableResult
    func interrupt(_ sessionId: String) -> Bool {
        let ok = client.post("interrupt", ["session": .string(sessionId)])
        if !ok { lastError = "Not connected to your PC" }
        return ok
    }

    @discardableResult
    func answer(_ request: PermissionRequest, in sessionId: String, allow: Bool) -> Bool {
        let ok = client.post("permission", ["session": .string(sessionId), "id": .string(request.id), "allow": .bool(allow)])
        if ok { request.allowed = allow } else { lastError = "Not connected to your PC. Your answer wasn\u{2019}t delivered." }
        return ok
    }

    func update(_ sessionId: String, title: String? = nil, pinned: Bool? = nil, model: String? = nil,
                effort: String? = nil, permissionMode: String? = nil) {
        var params: [String: JSONValue] = ["session": .string(sessionId)]
        if let title { params["title"] = .string(title) }
        if let pinned { params["pinned"] = .bool(pinned) }
        if let model { params["model"] = .string(model) }
        if let effort { params["effort"] = .string(effort) }
        if let permissionMode { params["permissionMode"] = .string(permissionMode) }
        guard client.post("update", params) else {
            lastError = "Not connected to your PC. The change wasn\u{2019}t saved."
            return
        }
        // Optimistic: the bridge's `session` push confirms (or corrects) it.
        guard var s = session(sessionId) else { return }
        if let title { s.title = title }
        if let pinned { s.pinned = pinned }
        if let model { s.model = model }
        if let effort { s.effort = effort }
        if let permissionMode { s.permissionMode = permissionMode }
        upsert(s)
    }

    func delete(_ sessionId: String) {
        guard client.post("delete", ["session": .string(sessionId)]) else {
            lastError = "Not connected to your PC. Reconnect to delete this session."
            return
        }
        removeLocal(sessionId)
    }
}

/// Disk cache: sessions.json + events/<session>.jsonl (raw bridge events). All state lives on one serial queue;
/// appends are buffered and flushed about every 200 ms, the session list is saved debounced.
final class EventCache: @unchecked Sendable {
    private let root: URL
    private let writes: Bool
    private let queue = DispatchQueue(label: "linkup.cache", qos: .utility)
    // Everything below is confined to `queue`.
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var pending: [String: Data] = [:]
    private var deleted: Set<String> = []
    private var flushScheduled = false
    private var sessionsToSave: [SessionInfo]?
    private var sessionsSaveScheduled = false

    /// writes == false (screenshot fixtures): reads work, nothing is ever written.
    init(writes: Bool) {
        self.writes = writes
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("Linkup", isDirectory: true)
        if writes { try? FileManager.default.createDirectory(at: root.appendingPathComponent("events"), withIntermediateDirectories: true) }
    }

    private func file(_ sid: String) -> URL { root.appendingPathComponent("events/\(sid).jsonl") }
    private var sessionsURL: URL { root.appendingPathComponent("sessions.json") }

    func loadSessions() -> [SessionInfo] {
        guard let data = try? Data(contentsOf: sessionsURL) else { return [] }
        return (try? JSONDecoder().decode([SessionInfo].self, from: data)) ?? []
    }

    /// Debounced (~0.5 s); the encoding happens off the main actor.
    func saveSessions(_ sessions: [SessionInfo]) {
        guard writes else { return }
        queue.async { [self] in
            sessionsToSave = sessions
            guard !sessionsSaveScheduled else { return }
            sessionsSaveScheduled = true
            queue.asyncAfter(deadline: .now() + 0.5) { [self] in flushLocked() }
        }
    }

    /// Reads a session's events. Blocks the caller (call it off the main actor), decodes with one shared decoder.
    func loadEvents(_ sid: String) -> [BridgeEvent] {
        queue.sync { () -> [BridgeEvent] in
            flushLocked()
            guard let data = try? Data(contentsOf: file(sid)) else { return [] }
            var out: [BridgeEvent] = []
            out.reserveCapacity(1024)
            for line in data.split(separator: 0x0A) {
                if let raw = try? decoder.decode([String: JSONValue].self, from: Data(line)) { out.append(BridgeEvent(json: raw)) }
            }
            return out
        }
    }

    func append(_ raw: [String: JSONValue], to sid: String) {
        guard writes else { return }
        queue.async { [self] in
            guard !deleted.contains(sid), var data = try? encoder.encode(raw) else { return }
            data.append(0x0A)
            pending[sid, default: Data()].append(data)
            guard !flushScheduled else { return }
            flushScheduled = true
            queue.asyncAfter(deadline: .now() + 0.2) { [self] in flushLocked() }
        }
    }

    func deleteEvents(_ sid: String) {
        guard writes else { return }
        queue.async { [self] in
            deleted.insert(sid)
            pending[sid] = nil
            try? FileManager.default.removeItem(at: file(sid))
        }
    }

    /// Drops cache files of sessions the bridge no longer lists.
    func prune(keeping ids: Set<String>) {
        guard writes else { return }
        queue.async { [self] in
            let dir = root.appendingPathComponent("events")
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
            for f in files where f.pathExtension == "jsonl" && !ids.contains(f.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }

    /// Synchronously writes everything buffered (app is going to the background).
    func flush() {
        guard writes else { return }
        queue.sync { flushLocked() }
    }

    private func flushLocked() {
        flushScheduled = false
        let batch = pending
        pending = [:]
        for (sid, data) in batch where !deleted.contains(sid) { write(data, to: file(sid)) }
        sessionsSaveScheduled = false
        if let list = sessionsToSave {
            sessionsToSave = nil
            if let data = try? encoder.encode(list) { try? data.write(to: sessionsURL, options: .atomic) }
        }
    }

    private func write(_ data: Data, to url: URL) {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {}
        } else {
            try? data.write(to: url)
        }
    }
}
