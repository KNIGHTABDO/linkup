import Foundation
import Observation

/// A session's conversation, built incrementally from bridge events. Every streaming piece is its own observable
/// object, so a token arriving in one text block re-renders only that block.
@MainActor @Observable
final class Transcript {
    let sessionId: String
    private(set) var items: [TranscriptItem] = []
    private(set) var lastSeq = 0
    /// Set while the agent works on a turn.
    private(set) var liveTurn: AssistantTurn?
    private(set) var pendingPermissions: [PermissionRequest] = []

    @ObservationIgnored private var tools: [String: ToolCall] = [:]
    @ObservationIgnored private var thinking: [String: ThinkingBlock] = [:]
    @ObservationIgnored private var texts: [String: TextBlock] = [:]
    @ObservationIgnored private var partialInputs: [String: String] = [:]

    init(sessionId: String) { self.sessionId = sessionId }

    var isWorking: Bool { liveTurn != nil }
    var lastAssistantTurn: AssistantTurn? {
        for item in items.reversed() { if case .assistant(let t) = item { return t } }
        return nil
    }

    func reset() {
        items = []
        lastSeq = 0
        liveTurn = nil
        pendingPermissions = []
        tools = [:]; thinking = [:]; texts = [:]; partialInputs = [:]
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func apply(_ e: BridgeEvent) {
        guard e.seq == 0 || e.seq > lastSeq else { return }      // replays after reconnect are idempotent
        if e.seq > 0 { lastSeq = e.seq }
        let date = Date(timeIntervalSince1970: e.ts)
        switch e.type {
        case "user":
            let atts = (e["attachments"]?.array ?? []).compactMap { a -> AttachmentRef? in
                guard let url = a["url"]?.string else { return nil }
                return AttachmentRef(name: a["name"]?.string ?? "file", url: url, mime: a["mime"]?.string)
            }
            items.append(.user(UserMessage(id: "u\(e.seq)", text: e["text"]?.string ?? "", attachments: atts, date: date)))
        case "turn.start":
            startTurn(date)
        case "status":
            let turn = liveTurn ?? startTurn(date)
            turn.phase = TurnPhase(rawValue: e["state"]?.string ?? "") ?? turn.phase
            if let detail = e["detail"]?.string, turn.phase == .error { turn.parts.append(.error(id: "err\(e.seq)", detail)) }
        case "thinking.start":
            let block = ThinkingBlock(id: blockId(e))
            thinking[block.id] = block
            turn(date).parts.append(.thinking(block))
        case "thinking.delta":
            let id = blockId(e)
            let block = thinking[id] ?? {
                let b = ThinkingBlock(id: id); thinking[id] = b; turn(date).parts.append(.thinking(b)); return b
            }()
            block.text += e["text"]?.string ?? ""
        case "thinking.end":
            thinking[blockId(e)]?.isActive = false
        case "text.start":
            let block = TextBlock(id: blockId(e))
            texts[block.id] = block
            if let parent = e["parent"]?.string, let tool = tools[parent] { tool.childText.append(block) }
            else { turn(date).parts.append(.text(block)) }
        case "text.delta":
            let id = blockId(e)
            let block = texts[id] ?? {
                let b = TextBlock(id: id); texts[id] = b; turn(date).parts.append(.text(b)); return b
            }()
            block.text += e["text"]?.string ?? ""
        case "text.end":
            texts[blockId(e)]?.isActive = false
        case "tool.start":
            let id = e["id"]?.string ?? "t\(e.seq)"
            let tool = tools[id] ?? ToolCall(id: id, name: e["name"]?.string ?? "tool", started: date)
            tool.input = e["input"] ?? tool.input
            tools[id] = tool
            if let parent = e["parent"]?.string, let owner = tools[parent] { owner.children.append(tool) }
            else { turn(date).parts.append(.tool(tool)) }
        case "tool.input":
            guard let id = e["id"]?.string, let tool = tools[id] else { break }
            let partial = (partialInputs[id] ?? "") + (e["partial"]?.string ?? "")
            partialInputs[id] = partial
            tool.partialInput = partial
        case "tool.update":
            guard let id = e["id"]?.string else { break }
            let tool = tools[id] ?? {
                let t = ToolCall(id: id, name: e["name"]?.string ?? "tool", started: date)
                tools[id] = t; turn(date).parts.append(.tool(t)); return t
            }()
            if let input = e["input"], input.object?.isEmpty == false { tool.input = input }
            tool.partialInput = nil
        case "tool.end":
            guard let id = e["id"]?.string else { break }
            let tool = tools[id] ?? {
                let t = ToolCall(id: id, name: e["name"]?.string ?? "tool", started: date)
                tools[id] = t; turn(date).parts.append(.tool(t)); return t
            }()
            tool.output = e["output"]?.string ?? ""
            tool.isError = e["isError"]?.bool ?? false
            tool.images = (e["images"]?.array ?? []).compactMap(\.string)
            tool.finished = date
        case "artifact":
            let ref = ArtifactRef(id: e["id"]?.string ?? "a\(e.seq)", kind: e["kind"]?.string ?? "file",
                                  title: e["title"]?.string ?? "File", url: e["url"]?.string ?? "",
                                  path: e["path"]?.string, mime: e["mime"]?.string, size: e["size"]?.int)
            let target = e["tool"]?.string.flatMap { tools[$0] }
            target?.artifacts.append(ref)
            turn(date).parts.append(.artifact(ref))
        case "permission.request":
            let req = PermissionRequest(id: e["id"]?.string ?? "p\(e.seq)", tool: e["tool"]?.string ?? "tool",
                                        input: e["input"] ?? .null, reason: e["reason"]?.string)
            pendingPermissions.append(req)
            turn(date).parts.append(.permission(req))
        case "permission.resolved":
            let id = e["id"]?.string
            if let req = pendingPermissions.first(where: { $0.id == id }) { req.allowed = e["allow"]?.bool ?? false }
            pendingPermissions.removeAll { $0.id == id }
        case "usage":
            let turn = liveTurn ?? lastAssistantTurn
            turn?.usage = TurnUsage(input: (e["inputTokens"]?.int ?? 0) + (e["cacheRead"]?.int ?? 0) + (e["cacheWrite"]?.int ?? 0),
                                    output: e["outputTokens"]?.int ?? 0, costUsd: e["costUsd"]?.double)
        case "notice":
            if let text = e["text"]?.string { (liveTurn ?? lastAssistantTurn)?.parts.append(.notice(id: "n\(e.seq)", text)) }
            if e["kind"]?.string == "init" { liveTurn?.model = e["model"]?.string }
        case "error":
            turn(date).parts.append(.error(id: "e\(e.seq)", e["message"]?.string ?? "Something went wrong"))
        case "turn.end":
            if let turn = liveTurn {
                turn.finished = date
                turn.durationMs = e["durationMs"]?.int
                if let cost = e["costUsd"]?.double { turn.usage?.costUsd = cost }
                let reason = e["stopReason"]?.string ?? ""
                turn.phase = (e["isError"]?.bool ?? false) ? .error : (reason == "interrupted" ? .interrupted : .done)
                if let text = e["text"]?.string, !text.isEmpty, turn.phase == .error { turn.parts.append(.error(id: "te\(e.seq)", text)) }
                for case .thinking(let b) in turn.parts { b.isActive = false }
                for case .text(let b) in turn.parts { b.isActive = false }
                for case .tool(let t) in turn.parts where t.finished == nil { t.finished = date }
            }
            liveTurn = nil
            pendingPermissions.removeAll()
        default:
            break
        }
    }

    @discardableResult
    private func startTurn(_ date: Date) -> AssistantTurn {
        if let liveTurn { return liveTurn }
        let turn = AssistantTurn(id: "a\(lastSeq)", started: date)
        items.append(.assistant(turn))
        liveTurn = turn
        return turn
    }

    private func turn(_ date: Date) -> AssistantTurn { liveTurn ?? startTurn(date) }
    private func blockId(_ e: BridgeEvent) -> String { e["block"]?.string ?? "b\(e.seq)" }
}

enum TranscriptItem: Identifiable {
    case user(UserMessage)
    case assistant(AssistantTurn)

    var id: String {
        switch self {
        case .user(let m): m.id
        case .assistant(let t): t.id
        }
    }
}

struct UserMessage: Identifiable, Hashable {
    let id: String
    let text: String
    let attachments: [AttachmentRef]
    let date: Date
}

struct AttachmentRef: Hashable, Identifiable {
    let name: String
    /// Bridge-relative URL ("/linkup/files/…"): resolve with `LinkupClient.resolve(_:)`.
    let url: String
    let mime: String?
    var id: String { url }
    var isImage: Bool { mime?.hasPrefix("image/") ?? false }
}

enum TurnPhase: String {
    case requesting, running, idle, done, error, interrupted
}

struct TurnUsage: Hashable {
    var input: Int
    var output: Int
    var costUsd: Double?
}

@MainActor @Observable
final class AssistantTurn: Identifiable {
    let id: String
    let started: Date
    var parts: [TurnPart] = []
    var phase: TurnPhase = .requesting
    var finished: Date?
    var durationMs: Int?
    var usage: TurnUsage?
    var model: String?

    init(id: String, started: Date) {
        self.id = id
        self.started = started
    }

    var isLive: Bool { finished == nil && phase != .done && phase != .error && phase != .interrupted }

    /// Thinking blocks, tools and permissions in order: the "Summary" timeline.
    var activity: [TurnPart] {
        parts.filter { part -> Bool in
            switch part {
            case .text, .artifact: return false
            default: return true
            }
        }
    }
    var textBlocks: [TextBlock] {
        parts.compactMap { part -> TextBlock? in
            if case .text(let b) = part { return b }
            return nil
        }
    }
    var artifacts: [ArtifactRef] {
        parts.compactMap { part -> ArtifactRef? in
            if case .artifact(let a) = part { return a }
            return nil
        }
    }

    /// One line for the collapsed activity row: the latest thinking line or the tool running now.
    var activityLine: String {
        for part in parts.reversed() {
            switch part {
            case .tool(let t) where t.finished == nil: return t.presentation.activeTitle
            case .thinking(let b):
                let line = b.summaryLine
                if !line.isEmpty { return line }
            case .tool(let t): return t.presentation.doneTitle
            default: continue
            }
        }
        return phase == .requesting ? "Thinking\u{2026}" : "Working\u{2026}"
    }
}

enum TurnPart: Identifiable {
    case thinking(ThinkingBlock)
    case text(TextBlock)
    case tool(ToolCall)
    case artifact(ArtifactRef)
    case permission(PermissionRequest)
    case notice(id: String, String)
    case error(id: String, String)

    var id: String {
        switch self {
        case .thinking(let b): "th-\(b.id)"
        case .text(let b): "tx-\(b.id)"
        case .tool(let t): "to-\(t.id)"
        case .artifact(let a): "ar-\(a.id)"
        case .permission(let p): "pe-\(p.id)"
        case .notice(let id, _): id
        case .error(let id, _): id
        }
    }
}

@MainActor @Observable
final class ThinkingBlock: Identifiable {
    let id: String
    var text = ""
    var isActive = true
    init(id: String) { self.id = id }

    /// Latest non-empty line, without markdown emphasis (Claude's thinking updates arrive as short lines).
    var summaryLine: String {
        let line = text.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        return line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
    }
}

@MainActor @Observable
final class TextBlock: Identifiable {
    let id: String
    var text = ""
    var isActive = true
    init(id: String) { self.id = id }
}

@MainActor @Observable
final class ToolCall: Identifiable {
    let id: String
    let name: String
    let started: Date
    var input: JSONValue = .object([:])
    /// Raw JSON of the input while it is still streaming in.
    var partialInput: String?
    var output: String?
    var isError = false
    var images: [String] = []
    var artifacts: [ArtifactRef] = []
    var finished: Date?
    /// Sub-agent work (Claude Code Task tool): nested tool calls and text.
    var children: [ToolCall] = []
    var childText: [TextBlock] = []

    init(id: String, name: String, started: Date) {
        self.id = id
        self.name = name
        self.started = started
    }

    var isRunning: Bool { finished == nil }
    var presentation: ToolPresentation { ToolPresentation(tool: self) }
}

@MainActor @Observable
final class PermissionRequest: Identifiable {
    let id: String
    let tool: String
    let input: JSONValue
    let reason: String?
    /// nil while waiting for the user.
    var allowed: Bool?
    init(id: String, tool: String, input: JSONValue, reason: String?) {
        self.id = id
        self.tool = tool
        self.input = input
        self.reason = reason
    }
}

struct ArtifactRef: Hashable, Identifiable {
    let id: String
    /// html | svg | markdown | image | pdf | video | audio | code | file
    let kind: String
    let title: String
    /// Bridge-relative URL: resolve with `LinkupClient.resolve(_:)`.
    let url: String
    let path: String?
    let mime: String?
    let size: Int?
}
