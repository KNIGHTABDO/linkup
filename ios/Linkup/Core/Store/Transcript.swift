import Foundation
import Observation

/// A session's conversation, built incrementally from bridge events. Every streaming piece is its own observable
/// object, so a token arriving in one text block re-renders only that block.
@MainActor @Observable
final class Transcript {
    let sessionId: String
    private(set) var items: [TranscriptItem] = []
    private(set) var lastSeq = 0
    /// True while the cached events are still being loaded from disk (show a loading state, not the greeting).
    var isLoading = false
    /// Set while the agent works on a turn.
    private(set) var liveTurn: AssistantTurn?
    private(set) var pendingPermissions: [PermissionRequest] = []

    @ObservationIgnored private var tools: [String: ToolCall] = [:]
    @ObservationIgnored private var thinking: [String: ThinkingBlock] = [:]
    @ObservationIgnored private var texts: [String: TextBlock] = [:]
    @ObservationIgnored private var partialInputs: [String: String] = [:]
    /// Seq of the event being applied (0 when the event carries none) and the open block of each kind, for deltas
    /// that arrive without a block id.
    @ObservationIgnored private var eventSeq = 0
    @ObservationIgnored private var openThinkingId: String?
    @ObservationIgnored private var openTextId: String?

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
        resetBlockMaps()
    }

    private func resetBlockMaps() {
        tools = [:]; thinking = [:]; texts = [:]; partialInputs = [:]
        openThinkingId = nil; openTextId = nil
    }

    /// True when `seq` skips events we never received (the caller re-subscribes to backfill them).
    func hasGap(before seq: Int) -> Bool { seq > 0 && lastSeq > 0 && seq > lastSeq + 1 }

    /// The bridge says this session is idle but we still show a live turn (bridge restarted mid-turn, forked
    /// session): close it so "Working…" and the Stop button don't stay forever.
    func endStaleTurn() {
        guard liveTurn != nil else { return }
        finishTurn(Date(), phase: .interrupted, text: nil, durationMs: nil, cost: nil)
    }

    /// Applies one event. Returns false when it was a duplicate (already applied), so the caller doesn't cache it twice.
    @discardableResult
    func apply(_ e: BridgeEvent) -> Bool {
        guard e.seq == 0 || e.seq > lastSeq else { return false }      // replays after reconnect are idempotent
        if e.seq > 0 { lastSeq = e.seq }
        eventSeq = e.seq
        applyEvent(e)
        return true
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func applyEvent(_ e: BridgeEvent) {
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
            let state = TurnPhase(rawValue: e["state"]?.string ?? "")
            // "idle" after turn.end must not open a new turn; only working states start one.
            guard let turn = liveTurn ?? ((state == .requesting || state == .running) ? startTurn(date) : nil) else {
                if state == .error, let detail = e["detail"]?.string { lastAssistantTurn?.parts.append(.error(id: "err\(e.seq)", detail)) }
                break
            }
            // Only working states move the phase; "error"/"interrupted" statuses arrive mid-turn and the real end
            // is the turn.end event (otherwise the turn looks finished while it is still live).
            if state == .requesting || state == .running { turn.phase = state ?? turn.phase }
            if let detail = e["detail"]?.string, state == .error { turn.parts.append(.error(id: "err\(e.seq)", detail)) }
        case "thinking.start":
            let block = ThinkingBlock(id: blockId(e))
            thinking[block.id] = block
            openThinkingId = block.id
            if !isSubagent(e) { turn(date).parts.append(.thinking(block)) }
        case "thinking.delta":
            let id = e["block"]?.string ?? openThinkingId ?? "b\(e.seq)"
            let block = thinking[id] ?? {
                let b = ThinkingBlock(id: id); thinking[id] = b; openThinkingId = id
                if !isSubagent(e) { turn(date).parts.append(.thinking(b)) }
                return b
            }()
            block.text += e["text"]?.string ?? ""
        case "thinking.end":
            let id = e["block"]?.string ?? openThinkingId
            if let id { thinking[id]?.isActive = false }
            if id == openThinkingId { openThinkingId = nil }
        case "text.start":
            let block = TextBlock(id: blockId(e))
            texts[block.id] = block
            openTextId = block.id
            if let parent = e["parent"]?.string, let tool = tools[parent] { tool.childText.append(block) }
            else { turn(date).parts.append(.text(block)) }
        case "text.delta":
            let id = e["block"]?.string ?? openTextId ?? "b\(e.seq)"
            let block = texts[id] ?? {
                let b = TextBlock(id: id); texts[id] = b; openTextId = id
                turn(date).parts.append(.text(b)); return b
            }()
            block.text += e["text"]?.string ?? ""
        case "text.end":
            let id = e["block"]?.string ?? openTextId
            if let id { texts[id]?.isActive = false }
            if id == openTextId { openTextId = nil }
        case "tool.start":
            let id = e["id"]?.string ?? "t\(e.seq)"
            if let existing = tools[id] {
                // agy repeats tool.start for every step update: refresh the input, never add a second row.
                if let input = e["input"], input.object?.isEmpty == false { existing.input = input }
                break
            }
            let tool = ToolCall(id: id, name: e["name"]?.string ?? "tool", started: date)
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
            let tool = tools[id] ?? makeTool(id: id, e, date)
            if let input = e["input"], input.object?.isEmpty == false { tool.input = input }
            tool.partialInput = nil
        case "tool.end":
            guard let id = e["id"]?.string else { break }
            let tool = tools[id] ?? makeTool(id: id, e, date)
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
            turn?.usage = TurnUsage(input: e["inputTokens"]?.int ?? 0, output: e["outputTokens"]?.int ?? 0,
                                    costUsd: e["costUsd"]?.double,
                                    cached: (e["cacheRead"]?.int ?? 0) + (e["cacheWrite"]?.int ?? 0))
        case "notice":
            if let text = e["text"]?.string { quietTurn(date).parts.append(.notice(id: "n\(e.seq)", text)) }
            if e["kind"]?.string == "init" { liveTurn?.model = e["model"]?.string }
        case "error":
            quietTurn(date).parts.append(.error(id: "e\(e.seq)", e["message"]?.string ?? "Something went wrong"))
        case "turn.end":
            let reason = (e["stopReason"]?.string ?? "").lowercased()
            let cancelled = ["interrupted", "cancelled", "canceled", "stopped"].contains(reason)
            let phase: TurnPhase = cancelled ? .interrupted : ((e["isError"]?.bool ?? false) ? .error : .done)
            finishTurn(date, phase: phase, text: e["text"]?.string, durationMs: e["durationMs"]?.int,
                       cost: e["costUsd"]?.double)
        default:
            break
        }
    }

    private func finishTurn(_ date: Date, phase: TurnPhase, text: String?, durationMs: Int?, cost: Double?) {
        if let turn = liveTurn {
            turn.finished = date
            turn.durationMs = durationMs
            if let cost { turn.usage?.costUsd = cost }
            turn.phase = phase
            if let text, !text.isEmpty, phase == .error { turn.parts.append(.error(id: "te\(eventSeq)", text)) }
            for part in turn.parts {
                switch part {
                case .thinking(let b): b.isActive = false
                case .text(let b): b.isActive = false
                case .tool(let t) where t.finished == nil:
                    t.finished = date
                    t.wasStopped = phase != .done
                case .permission(let p) where p.allowed == nil:
                    p.allowed = false
                default: break
                }
            }
        }
        liveTurn = nil
        pendingPermissions.removeAll()
    }

    /// Tool announced by an update/end event that never had a start (or whose start was missed).
    private func makeTool(id: String, _ e: BridgeEvent, _ date: Date) -> ToolCall {
        let t = ToolCall(id: id, name: e["name"]?.string ?? "tool", started: date)
        tools[id] = t
        if let parent = e["parent"]?.string, let owner = tools[parent] { owner.children.append(t) }
        else { turn(date).parts.append(.tool(t)) }
        return t
    }

    @discardableResult
    private func startTurn(_ date: Date) -> AssistantTurn {
        if let liveTurn { return liveTurn }
        resetBlockMaps()       // agy reuses block/tool ids in every process: a new turn never inherits old blocks
        let turn = AssistantTurn(id: newTurnId(), started: date)
        items.append(.assistant(turn))
        liveTurn = turn
        return turn
    }

    /// Stable across reloads (derived from the bridge's seq) and unique within the session.
    private func newTurnId() -> String {
        eventSeq > 0 ? "a\(eventSeq)" : "a0-\(items.count)"
    }

    private func turn(_ date: Date) -> AssistantTurn { liveTurn ?? startTurn(date) }

    /// Where a notice or error goes: the live turn, else the assistant turn that closes the transcript, else a new
    /// finished turn (so it still shows, e.g. the target of a hand-off before anything was said). Never opens a live turn.
    private func quietTurn(_ date: Date) -> AssistantTurn {
        if let liveTurn { return liveTurn }
        if case .assistant(let t)? = items.last { return t }
        let t = AssistantTurn(id: eventSeq > 0 ? "n\(eventSeq)" : "n0-\(items.count)", started: date)
        t.finished = date
        t.phase = .done
        items.append(.assistant(t))
        return t
    }

    /// Sub-agent thinking belongs to the owner tool, not to the main turn's timeline.
    private func isSubagent(_ e: BridgeEvent) -> Bool {
        guard let parent = e["parent"]?.string else { return false }
        return tools[parent] != nil
    }

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
    /// Fresh (uncached) input tokens.
    var input: Int
    var output: Int
    var costUsd: Double?
    /// Prompt-cache reads + writes. Kept apart: on a warm cache they are 100x the real turn size.
    var cached: Int = 0
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
            case .thinking(let b): return b.isActive || !b.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    /// The turn ended (stopped or failed) before this tool reported a result.
    var wasStopped = false
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
