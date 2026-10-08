import SwiftUI

extension AttachmentRef {
    /// The wire form `SessionStore.send(_:to:attachments:)` expects, so Resend/Retry keep the original files.
    var sendPayload: [String: JSONValue] {
        var dict: [String: JSONValue] = ["name": .string(name), "url": .string(url)]
        if let mime { dict["mime"] = .string(mime) }
        return dict
    }
}

// MARK: - User bubble

/// User bubble: right-aligned, Theme.userBubble, radius 22, padding 14x12, Theme.sans(17).
struct UserBubble: View {
    let message: UserMessage
    var sessionId: String? = nil

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @State private var expanded = false

    private static let collapseCharacters = 700
    private static let collapsedLines = 10

    private var imageAttachments: [AttachmentRef] {
        message.attachments.filter(\.isImage)
    }

    private var otherAttachments: [AttachmentRef] {
        message.attachments.filter { !$0.isImage }
    }

    private var isLong: Bool {
        message.text.count > Self.collapseCharacters
            || message.text.split(separator: "\n", omittingEmptySubsequences: false).count > Self.collapsedLines + 2
    }

    var body: some View {
        HStack {
            Spacer(minLength: 48)

            VStack(alignment: .trailing, spacing: 8) {
                // Image attachments above the text as rounded thumbnails
                if !imageAttachments.isEmpty {
                    if imageAttachments.count == 1, let first = imageAttachments.first {
                        RemoteImageView(url: first.url)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(imageAttachments) { att in
                                    RemoteImageView(url: att.url)
                                        .frame(width: 120, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                        }
                    }
                }

                // Other attachments as small capsules with doc icon + name
                if !otherAttachments.isEmpty {
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(otherAttachments) { att in
                            HStack(spacing: 6) {
                                Image(systemName: "doc")
                                    .font(Theme.sans(13))
                                Text(att.name)
                                    .font(Theme.sans(13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1), in: Capsule())
                        }
                    }
                }

                // Text content, laid out in its own direction (Arabic/Darija right-to-left)
                if !message.text.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.text)
                            .font(Theme.sans(17))
                            .foregroundStyle(Theme.text)
                            .lineLimit(isLong && !expanded ? Self.collapsedLines : nil)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)

                        if isLong {
                            Button {
                                withAnimation(.snappy) { expanded.toggle() }
                            } label: {
                                Text(expanded ? "Show less" : "Show more")
                                    .font(Theme.sans(14, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .environment(\.layoutDirection, message.text.dominantLayoutDirection)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: 22))
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.text
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    ui.toast = "Copied"
                } label: {
                    Label("Copy", systemImage: "square.on.square")
                }

                // The composer observes .linkupComposerSetText and fills its input with this text.
                Button {
                    NotificationCenter.default.post(name: .linkupComposerSetText, object: message.text)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Edit & resend", systemImage: "pencil")
                }

                if let sid = sessionId {
                    Button {
                        resend(in: sid)
                    } label: {
                        Label("Resend", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func resend(in sid: String) {
        guard !store.transcript(for: sid).isWorking else {
            ui.toast = "Wait for the reply to finish"
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.send(message.text, to: sid, attachments: message.attachments.map(\.sendPayload))
    }
}

// MARK: - Assistant turn

/// One agent turn, Claude-app style: left-aligned, full width.
///
/// Per-token cost: this view never reads `TextBlock.text` or session data in its body. Text lives in
/// `TextBlockView` (re-renders alone), the header and footer read the store themselves.
struct AssistantTurnView: View {
    let turn: AssistantTurn
    let sessionId: String

    @Environment(SessionStore.self) private var store

    /// Activity row rule: always while live; afterwards hidden in chat-mode sessions unless something failed.
    private var showsActivityRow: Bool {
        if turn.isLive { return true }
        let activity = turn.activity
        if activity.isEmpty { return false }
        if store.session(sessionId)?.mode == "chat" { return hasErrors }
        return true
    }

    private var hasErrors: Bool {
        if turn.phase == .error { return true }
        return turn.parts.contains { part in
            switch part {
            case .error: true
            case .tool(let t): t.isError
            default: false
            }
        }
    }

    private var hasAnswerContent: Bool {
        !turn.textBlocks.isEmpty || !turn.artifacts.isEmpty || !turn.isLive
    }

    var body: some View {
        let showActivity = showsActivityRow
        let live = turn.isLive

        VStack(alignment: .leading, spacing: 14) {
            if showActivity {
                ActivityRow(turn: turn)
                    .transition(.opacity)
            }

            if hasAnswerContent {
                TurnHeader(turn: turn, sessionId: sessionId)
            }

            ForEach(turn.parts) { part in
                partView(part, live: live)
            }

            if !live {
                TurnFooter(turn: turn, sessionId: sessionId)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.3), value: showActivity)
        .animation(.smooth(duration: 0.3), value: live)
        .animation(.smooth(duration: 0.3), value: turn.artifacts.count)
        // Stable by session id: building this per body does not invalidate the environment.
        .environment(\.cardActions, CardActions(id: sessionId, send: { text in store.send(text, to: sessionId) }))
    }

    @ViewBuilder
    private func partView(_ part: TurnPart, live: Bool) -> some View {
        switch part {
        case .text(let block):
            TextBlockView(block: block, turnLive: live)
        case .artifact(let a):
            ArtifactCard(artifact: a)
                .transition(.opacity)
        case .permission(let p):
            // Kept after it is answered so the Allowed/Denied state stays visible; an unanswered request
            // on a finished turn is expired and hidden.
            if p.allowed != nil || live {
                PermissionCard(request: p, sessionId: sessionId)
            }
        case .error(_, let msg):
            TurnErrorRow(message: msg)
        case .notice(_, let text):
            HStack {
                Spacer()
                Text(text)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                Spacer()
            }
        case .thinking, .tool:
            // Thinking and tools are rendered in the activity row / summary timeline
            EmptyView()
        }
    }
}

/// One streamed text block. The only view that reads `block.text`, so token updates re-render just this.
struct TextBlockView: View {
    let block: TextBlock
    /// False once the turn ended or was stopped: a block left "active" must not keep its caret.
    var turnLive = true

    var body: some View {
        let streaming = block.isActive && turnLive
        if !block.text.isEmpty || streaming {
            RichTextView(text: block.text, isStreaming: streaming)
        }
    }
}

/// Streaming-safe markdown renderer in the serif agent voice (plain markdown, no cards).
struct MarkdownView: View {
    let text: String
    var isStreaming = false

    var body: some View {
        RichTextView(text: text, isStreaming: isStreaming, parseCards: false)
    }
}

// MARK: - Header

/// Tiny agent logo + model name above the first answer, plus the pinned badge.
private struct TurnHeader: View {
    let turn: AssistantTurn
    let sessionId: String

    @Environment(SessionStore.self) private var store

    private var modelName: String {
        let session = store.session(sessionId)
        let agent = store.agent(session?.agent ?? "claude")
        let effective = turn.model ?? session?.model ?? agent?.defaultModel
        if let model = effective.flatMap({ agent?.model($0) }) {
            let resolved = model.description?.components(separatedBy: "\u{00B7}").first?.trimmingCharacters(in: .whitespaces)
            return (model.id == "default" ? resolved : nil) ?? model.name
        }
        return effective ?? "Model"
    }

    var body: some View {
        let isPinned = PinnedStore.shared.isPinned(turnId: turn.id, in: sessionId)

        HStack(spacing: 6) {
            AgentLogo(agent: store.session(sessionId)?.agent ?? "claude", size: 16)

            Text(modelName)
                .font(Theme.sans(12, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)

            if isPinned {
                HStack(spacing: 3) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                    Text("Pinned")
                        .font(Theme.sans(10, weight: .medium))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.accent.opacity(0.12), in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Error row

/// API/rate-limit failures as a clear row with a title and the readable message, never raw JSON.
private struct TurnErrorRow: View {
    let message: String

    private var parsed: (title: String, detail: String) {
        var detail = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pull "message" out of an embedded JSON body, e.g. `API Error: 429 {"error":{"message":"..."}}`.
        if let brace = detail.firstIndex(of: "{"),
           let data = String(detail[brace...]).data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let m = error["message"] as? String, !m.isEmpty {
                detail = m
            } else if let m = object["message"] as? String, !m.isEmpty {
                detail = m
            } else if let m = object["error"] as? String, !m.isEmpty {
                detail = m
            }
        }

        let lower = message.lowercased()
        let title: String
        if lower.contains("rate limit") || lower.contains("rate_limit") || lower.contains("429")
            || lower.contains("usage limit") || lower.contains("quota") {
            title = "Rate limit reached"
        } else if lower.contains("overloaded") || lower.contains("529") || lower.contains("503") {
            title = "The model is overloaded"
        } else if lower.contains("401") || lower.contains("unauthorized") || lower.contains("authentication")
            || lower.contains("not logged in") || lower.contains("log in") {
            title = "Sign-in required"
        } else if lower.contains("timeout") || lower.contains("timed out") || lower.contains("network") {
            title = "Connection problem"
        } else {
            title = "Something went wrong"
        }
        return (title, detail)
    }

    var body: some View {
        let info = parsed
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Theme.sans(15))
                .foregroundStyle(Theme.danger)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(info.title)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(info.detail)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.danger.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Footer

/// Everything under a finished answer: stopped marker, dev-server chips, actions, stats. Built only after
/// the turn ends, so streaming never pays for it.
private struct TurnFooter: View {
    let turn: AssistantTurn
    let sessionId: String

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @State private var ports: [Int] = []

    private var shareText: String {
        let text = turn.textBlocks.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !text.isEmpty { return text }
        return turn.artifacts.map(\.title).joined(separator: "\n")
    }

    private var otherAgents: [AgentInfo] {
        let currentAgentId = store.session(sessionId)?.agent ?? "claude"
        let list = store.agents.filter { $0.id != currentAgentId && $0.available }
        if !list.isEmpty { return list }
        return AgentKind.allCases
            .filter { $0.rawValue != currentAgentId }
            .map { AgentInfo(id: $0.rawValue, name: $0.title, available: true) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if turn.phase == .interrupted {
                Label("Stopped", systemImage: "stop.circle")
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
            }

            if !ports.isEmpty {
                HStack(spacing: 8) {
                    ForEach(ports, id: \.self) { port in
                        Button {
                            ui.previewPort = port
                        } label: {
                            Label("Preview localhost:\(port)", systemImage: "safari")
                                .font(Theme.sans(14, weight: .medium))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }

            actionRow
        }
        .task(id: turn.id) { await detectDevServers() }
    }

    // MARK: Actions

    private var actionRow: some View {
        let text = shareText

        return HStack(spacing: 0) {
            if !text.isEmpty {
                footerButton("square.on.square", label: "Copy response") {
                    UIPasteboard.general.string = text
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    ui.toast = "Copied"
                }

                ShareLink(item: text) {
                    footerIcon("square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share response")
            }

            footerButton("arrow.clockwise", label: "Retry") { retryTurn() }

            optionsMenu

            Spacer(minLength: 8)

            stats
        }
        .padding(.leading, -12)
    }

    private func footerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19))
            .foregroundStyle(Theme.secondaryText)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func footerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { footerIcon(symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private var optionsMenu: some View {
        Menu {
            Button {
                Task {
                    do {
                        let forked = try await store.fork(sessionId)
                        ui.openSession(forked.id)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        ui.toast = "Conversation forked"
                    } catch {
                        ui.toast = error.localizedDescription
                    }
                }
            } label: {
                Label("Fork conversation", systemImage: "arrow.triangle.branch")
            }

            let agents = otherAgents
            if !agents.isEmpty {
                Menu {
                    ForEach(agents, id: \.id) { agent in
                        Button {
                            Task {
                                do {
                                    let handedOff = try await store.handoff(sessionId, to: agent.id, model: nil)
                                    ui.openSession(handedOff.id)
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                } catch {
                                    ui.toast = error.localizedDescription
                                }
                            }
                        } label: {
                            Label {
                                Text(agent.name)
                            } icon: {
                                AgentLogo(agent: agent.id, size: 16)
                            }
                        }
                    }
                } label: {
                    Label("Continue with\u{2026}", systemImage: "arrow.right.arrow.left")
                }
            }

            Divider()

            Button {
                withAnimation(.snappy) {
                    PinnedStore.shared.togglePin(turnId: turn.id, in: sessionId)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                let isPinned = PinnedStore.shared.isPinned(turnId: turn.id, in: sessionId)
                Label(isPinned ? "Unpin message" : "Pin message", systemImage: isPinned ? "pin.slash" : "pin")
            }

            Divider()

            Menu {
                let transcript = store.transcript(for: sessionId)
                let title = store.session(sessionId)?.displayTitle

                ShareLink(item: ChatExportFile(transcript: transcript, title: title, kind: .markdown),
                          preview: SharePreview(title ?? "Linkup chat")) {
                    Label("Export as Markdown (.md)", systemImage: "doc.text")
                }

                ShareLink(item: ChatExportFile(transcript: transcript, title: title, kind: .pdf),
                          preview: SharePreview(title ?? "Linkup chat")) {
                    Label("Export as PDF (.pdf)", systemImage: "doc.richtext")
                }
            } label: {
                Label("Export chat", systemImage: "square.and.arrow.up")
            }
        } label: {
            footerIcon("ellipsis")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Turn options")
    }

    private func retryTurn() {
        let transcript = store.transcript(for: sessionId)
        guard !transcript.isWorking else {
            ui.toast = "Wait for the reply to finish"
            return
        }
        guard let idx = transcript.items.firstIndex(where: { item in
            if case .assistant(let t) = item { return t.id == turn.id }
            return false
        }) else { return }

        for item in transcript.items[..<idx].reversed() {
            if case .user(let userMsg) = item {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                store.send(userMsg.text, to: sessionId, attachments: userMsg.attachments.map(\.sendPayload))
                return
            }
        }
    }

    // MARK: Dev servers

    /// Local dev servers the agent started or mentioned, scanned once when the turn is finished.
    private func detectDevServers() async {
        var text = turn.textBlocks.map(\.text).joined(separator: "\n")
        for part in turn.parts {
            if case .tool(let t) = part, let out = t.output { text += "\n" + out.prefix(20_000) }
        }
        let source = text
        let found = await Task.detached(priority: .utility) {
            Array(DevServerDetector.ports(in: source).filter { $0 >= 1024 && $0 != 8890 }.prefix(3))
        }.value
        if found != ports { ports = found }
    }

    // MARK: Stats

    private var stats: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if let line = statsLine {
                Text(line)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let cached = cachedLine {
                Text(cached)
                    .font(Theme.sans(10))
                    .foregroundStyle(Theme.tertiaryText.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .combine)
    }

    private var statsLine: String? {
        var parts: [String] = []
        parts.append(turn.started.formatted(date: .omitted, time: .shortened))
        if let ms = turn.durationMs { parts.append(Self.duration(ms)) }
        if let usage = turn.usage {
            let total = usage.input + usage.output
            if total > 0 { parts.append("\(Self.compact(total)) tokens") }
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var cachedLine: String? {
        guard let cached = turn.usage?.cached, cached > 0 else { return nil }
        return "\(Self.compact(cached)) cached"
    }

    private static func duration(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let seconds = ms / 1000
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private static func compact(_ n: Int) -> String {
        guard n >= 1000 else { return "\(n)" }
        return "\((Double(n) / 1000).formatted(.number.precision(.fractionLength(1))))k"
    }
}
