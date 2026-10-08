import Foundation

// Projects, files, git, CI, schedules, multi-agent ops and live plan usage. Every call is one bridge op
// (see bridge/linkup_bridge/server.py docstring) and returns typed models.

struct FileEntry: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var path: String
    var isDir: Bool
    var size: Int?
    var modified: Double?
    var id: String { path }
}

struct FileContent: Codable, Hashable, Sendable {
    var path: String
    /// Text files (≤ 2 MB); nil for binaries.
    var text: String?
    /// Bridge-relative URL for images/PDFs/HTML (resolve with LinkupClient.resolve).
    var url: String?
    var size: Int?
    var language: String?
    var truncated: Bool?
}

struct GitFileChange: Codable, Hashable, Identifiable, Sendable {
    var path: String
    /// Porcelain code: "M", "A", "D", "R", "??"
    var status: String
    var staged: Bool?
    var id: String { path }
}

struct GitStatus: Codable, Hashable, Sendable {
    var isRepo: Bool
    var branch: String?
    var ahead: Int?
    var behind: Int?
    var remote: String?
    var files: [GitFileChange]
    var clean: Bool { files.isEmpty }
}

struct GitCommit: Codable, Hashable, Identifiable, Sendable {
    var hash: String
    var short: String
    var subject: String
    var author: String?
    var date: Double?
    var id: String { hash }
}

struct CIRun: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var name: String?
    var title: String?
    var status: String?
    var conclusion: String?
    var branch: String?
    var event: String?
    var url: String?
    var created: Double?
    /// Release IPA / screenshots artifacts when present.
    var artifacts: [String]?
}

struct ScheduleInfo: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var agent: String
    var model: String?
    var cwd: String?
    var prompt: String
    /// "HH:MM" local time on the PC.
    var time: String
    /// 1 = Monday … 7 = Sunday; empty = every day.
    var days: [Int]
    var enabled: Bool
    var lastRun: Double?
    var nextRun: Double?
    var lastSessionId: String?
}

struct AgyModelQuota: Codable, Hashable, Identifiable, Sendable {
    var name: String
    /// 0…1 remaining, when Antigravity reports it.
    var remaining: Double?
    var resetsAt: Double?
    var id: String { name }
}

struct AgyUsage: Codable, Hashable, Sendable {
    /// Exactly what Antigravity shows, e.g. "Out of credits" or "1,240 credits".
    var credits: String?
    var status: String?
    var models: [AgyModelQuota]?
    var at: Double?
}

struct ClaudePlanUsage: Codable, Hashable, Sendable {
    var fiveHour: RateLimitWindow?
    var sevenDay: RateLimitWindow?
    var sevenDayOpus: RateLimitWindow?
    var sevenDaySonnet: RateLimitWindow?
    var subscription: String?
    var at: Double?
}

extension UsageSnapshot {
    /// Polled every minute by the bridge (fresh even when nothing ran).
    var plan: ClaudePlanUsage? { claudePlan }
}

extension SessionStore {
    /// nil when the reply has no such field; throws (instead of silently returning nothing) when it is there but unreadable.
    private func decoded<T: Decodable>(_ type: T.Type, _ value: JSONValue?) throws -> T? {
        guard let value else { return nil }
        if case .null = value { return nil }
        do {
            return try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
        } catch {
            throw BridgeError(message: "Couldn\u{2019}t read your PC\u{2019}s reply. Update the Linkup bridge.")
        }
    }

    // MARK: Projects

    func createProject(name: String, git: Bool, readme: Bool, template: String?) async throws -> ProjectInfo {
        var params: [String: JSONValue] = ["name": .string(name), "git": .bool(git), "readme": .bool(readme)]
        if let template { params["template"] = .string(template) }
        let json = try await client.request("projects.create", params)
        guard let project = try decoded(ProjectInfo.self, json["project"]) else { throw BridgeError(message: "Project not created") }
        await loadProjects()
        return project
    }

    // MARK: Files

    func listFiles(_ path: String) async throws -> [FileEntry] {
        let json = try await client.request("fs.list", ["path": .string(path)])
        return try decoded([FileEntry].self, json["entries"]) ?? []
    }

    func readFile(_ path: String) async throws -> FileContent {
        let json = try await client.request("fs.read", ["path": .string(path)])
        guard let content = try decoded(FileContent.self, json["file"]) else { throw BridgeError(message: "Couldn\u{2019}t open the file") }
        return content
    }

    // MARK: Git & CI

    func gitStatus(_ path: String) async throws -> GitStatus {
        let json = try await client.request("git.status", ["path": .string(path)])
        return try decoded(GitStatus.self, json["status"]) ?? GitStatus(isRepo: false, files: [])
    }

    func gitDiff(_ path: String, file: String? = nil) async throws -> String {
        var params: [String: JSONValue] = ["path": .string(path)]
        if let file { params["file"] = .string(file) }
        return try await client.request("git.diff", params)["diff"]?.string ?? ""
    }

    func gitLog(_ path: String) async throws -> [GitCommit] {
        try decoded([GitCommit].self, try await client.request("git.log", ["path": .string(path)])["commits"]) ?? []
    }

    /// Stages everything and commits; returns the new commit.
    func gitCommit(_ path: String, message: String) async throws -> GitCommit? {
        try decoded(GitCommit.self, try await client.request("git.commit", ["path": .string(path), "message": .string(message)])["commit"])
    }

    /// Returns git's output.
    func gitPush(_ path: String) async throws -> String {
        try await client.request("git.push", ["path": .string(path)])["output"]?.string ?? ""
    }

    func ciRuns(_ path: String) async throws -> [CIRun] {
        try decoded([CIRun].self, try await client.request("gh.runs", ["path": .string(path)])["runs"]) ?? []
    }

    // MARK: Schedules

    func schedules() async throws -> [ScheduleInfo] {
        try decoded([ScheduleInfo].self, try await client.request("schedules")["schedules"]) ?? []
    }

    func saveSchedule(_ schedule: ScheduleInfo) async throws -> ScheduleInfo {
        guard case .object(var fields) = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(schedule)) else {
            throw BridgeError(message: "Invalid schedule")
        }
        // Cleared optional fields must reach the bridge as explicit nulls (the encoder omits them).
        if fields["model"] == nil { fields["model"] = .null }
        if fields["cwd"] == nil { fields["cwd"] = .null }
        let value = JSONValue.object(fields)
        let json = try await client.request("schedule.save", ["schedule": value])
        return try decoded(ScheduleInfo.self, json["schedule"]) ?? schedule
    }

    func deleteSchedule(_ id: String) async throws {
        try await client.request("schedule.delete", ["id": .string(id)])
    }

    /// Runs a schedule right now.
    func runSchedule(_ id: String) async throws -> SessionInfo? {
        let json = try await client.request("schedule.run", ["id": .string(id)])
        guard let s = try decoded(SessionInfo.self, json["session"]) else { return nil }
        ingest(["op": .string("session"), "session": json["session"] ?? .null])
        return s
    }

    // MARK: Multi-agent

    /// A copy of the conversation that can go its own way (Claude Code `--fork-session`; other agents get the
    /// transcript as context).
    func fork(_ sessionId: String) async throws -> SessionInfo {
        try sessionFrom(await client.request("fork", ["session": .string(sessionId)]))
    }

    /// Continues the conversation with another agent, which receives the transcript so far as context.
    func handoff(_ sessionId: String, to agent: String, model: String?) async throws -> SessionInfo {
        var params: [String: JSONValue] = ["session": .string(sessionId), "agent": .string(agent)]
        if let model { params["model"] = .string(model) }
        return try sessionFrom(await client.request("handoff", params))
    }

    /// The same prompt sent to several agents at once; returns their new sessions.
    func compare(_ prompt: String, agents: [String], cwd: String?) async throws -> [SessionInfo] {
        var params: [String: JSONValue] = ["prompt": .string(prompt), "agents": .array(agents.map(JSONValue.string))]
        if let cwd { params["cwd"] = .string(cwd) }
        let json = try await client.request("compare", params)
        let list = try decoded([SessionInfo].self, json["sessions"]) ?? []
        if case .array(let raw)? = json["sessions"] {
            for item in raw { ingest(["op": .string("session"), "session": item]) }
        }
        for s in list { open(s.id) }
        return list
    }

    /// New "chat mode" session: the agent answers with rich cards (maps, weather, recipes…).
    func createChat(agent: String, model: String?) async throws -> SessionInfo {
        var params: [String: JSONValue] = ["agent": .string(agent), "mode": .string("chat")]
        if let model { params["model"] = .string(model) }
        return try sessionFrom(await client.request("create", params))
    }

    private func sessionFrom(_ json: [String: JSONValue]) throws -> SessionInfo {
        guard let s = try decoded(SessionInfo.self, json["session"]) else { throw BridgeError(message: "Your PC couldn\u{2019}t start the session") }
        ingest(["op": .string("session"), "session": json["session"] ?? .null])
        open(s.id)
        return s
    }
}
