import Foundation

/// A conversation with one agent, as the bridge stores it.
struct SessionInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var agent: String
    var title: String?
    var model: String?
    var effort: String?
    var cwd: String?
    var nativeId: String?
    var permissionMode: String?
    var created: Double
    var updated: Double
    var pinned: Bool
    var status: String?
    var lastSeq: Int
    var preview: String?
    var unread: Int?
    var usage: SessionUsage?
    /// "chat" for rich-card chat sessions, nil for normal agent sessions.
    var mode: String?

    enum CodingKeys: String, CodingKey {
        case id, agent, title, model, effort, cwd, created, updated, pinned, status, preview, unread, usage, mode
        case nativeId = "native_id", permissionMode = "permission_mode", lastSeq = "last_seq"
    }

    var displayTitle: String { (title?.isEmpty == false ? title : nil) ?? "New session" }
    var isRunning: Bool { status == "running" }
    var hasUnread: Bool { (unread ?? 0) > 0 }
    var updatedDate: Date { Date(timeIntervalSince1970: updated) }
    var projectName: String? { cwd.map { URL(fileURLWithPath: $0).lastPathComponent } }
}

struct SessionUsage: Codable, Hashable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheRead: Int?
    var cacheWrite: Int?
    var thinkingTokens: Int?
    var costUsd: Double?
    /// Tokens of context the last request carried (input + cache).
    var lastInput: Int?
}

/// One agent's live catalog (models come from the agent itself: `claude` initialize, `agy models`, Hermes /v1/models).
struct AgentInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var available: Bool
    var models: [ModelInfo]?
    var defaultModel: String?
    var account: JSONValue?
    var commands: [CommandInfo]?
    var permissionModes: [String]?
    var supportsImages: Bool?
    var supportsInterrupt: Bool?
    var supportsPermissions: Bool?
    var error: String?
    var version: String?

    func model(_ id: String?) -> ModelInfo? { models?.first { $0.id == id } }
    var accountLabel: String? { account?["subscriptionType"]?.string }
}

struct ModelInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var description: String?
    var resolved: String?
    var efforts: [String]?
}

struct CommandInfo: Codable, Hashable, Sendable {
    var name: String?
    var description: String?
}

struct RateLimitWindow: Codable, Hashable, Sendable {
    /// 0…1 of the window used.
    var utilization: Double?
    var resetsAt: Double?
    var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: $0) } }
}

struct ClaudeRateLimit: Codable, Hashable, Sendable {
    var status: String?
    var fiveHour: RateLimitWindow?
    var sevenDay: RateLimitWindow?
    var resetsAt: Double?
    var limitType: String?
    var at: Double?
}

struct AgentTotals: Codable, Hashable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var costUsd: Double
    var sessions: Int
}

struct UsageSnapshot: Codable, Hashable, Sendable {
    /// Last rate-limit event Claude Code sent during a turn.
    var claude: ClaudeRateLimit?
    /// Plan usage polled every minute (same data as Claude Code's /usage).
    var claudePlan: ClaudePlanUsage?
    /// Antigravity credits / per-model quota.
    var agy: AgyUsage?
    var totals: [String: AgentTotals]?
    var at: Double?
}

struct ProjectInfo: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var path: String
    var id: String { path }
}

/// A Claude Code session started on the PC that can be continued from the phone.
struct HistoryItem: Codable, Hashable, Identifiable, Sendable {
    var nativeId: String
    var title: String
    var cwd: String?
    var updated: Double
    var messages: Int?
    var id: String { nativeId }
}

/// One event of a session's log (see bridge/linkup_bridge/agents/base.py for the vocabulary).
struct BridgeEvent: Sendable {
    var seq: Int
    var ts: Double
    var type: String
    var payload: [String: JSONValue]

    init(json: [String: JSONValue]) {
        payload = json
        seq = json["seq"]?.int ?? 0
        ts = json["ts"]?.double ?? Date().timeIntervalSince1970
        type = json["type"]?.string ?? ""
    }

    subscript(key: String) -> JSONValue? { payload[key] }
}

enum AgentKind: String, CaseIterable, Sendable {
    case claude, agy, hermes

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .agy: "Antigravity"
        case .hermes: "Hermes"
        }
    }

    /// SF Symbol used wherever the agent appears (rows, pickers, badges).
    var symbol: String {
        switch self {
        case .claude: "asterisk"
        case .agy: "sparkles"
        case .hermes: "bolt.horizontal.circle"
        }
    }
}
