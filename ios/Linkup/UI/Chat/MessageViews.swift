import SwiftUI

/// User bubble: right-aligned, Theme.userBubble, radius 22, padding 14x12, Theme.sans(17).
struct UserBubble: View {
    let message: UserMessage

    @Environment(UIState.self) private var ui

    private var imageAttachments: [AttachmentRef] {
        message.attachments.filter(\.isImage)
    }

    private var otherAttachments: [AttachmentRef] {
        message.attachments.filter { !$0.isImage }
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

                // Text content
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(Theme.sans(17))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// One agent turn, Claude-app style: left-aligned, full width.
struct AssistantTurnView: View {
    let turn: AssistantTurn
    let sessionId: String

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The activity row first if the turn has any activity or is live
            if !turn.activity.isEmpty || turn.isLive {
                Button {
                    ui.summaryTurn = turn
                } label: {
                    ActivityRow(turn: turn)
                }
                .buttonStyle(.plain)
            }

            // Parts in order
            ForEach(turn.parts) { part in
                switch part {
                case .text(let block):
                    MarkdownView(text: block.text, isStreaming: block.isActive)
                case .artifact(let a):
                    ArtifactCard(artifact: a)
                case .permission(let p):
                    if p.allowed == nil {
                        PermissionCard(request: p, sessionId: sessionId)
                    }
                case .error(_, let msg):
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.danger)
                        Text(msg)
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.danger.opacity(0.25), lineWidth: 1)
                    )
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

            // Action row when turn is finished
            if !turn.isLive {
                actionRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        let allText = turn.textBlocks.map(\.text).joined(separator: "\n\n")

        return HStack(spacing: 22) {
            Button {
                UIPasteboard.general.string = allText
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                ui.toast = "Copied"
            } label: {
                Image(systemName: "square.on.square")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy response")

            ShareLink(item: allText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share response")

            Button {
                retryTurn()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry")

            Spacer()

            if let stats = turnStats {
                Text(stats)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.top, 4)
    }

    private func retryTurn() {
        let transcript = store.transcript(for: sessionId)
        if let idx = transcript.items.firstIndex(where: { item in
            if case .assistant(let t) = item { return t.id == turn.id }
            return false
        }) {
            for item in transcript.items[..<idx].reversed() {
                if case .user(let userMsg) = item {
                    store.send(userMsg.text, to: sessionId)
                    break
                }
            }
        }
    }

    private var turnStats: String? {
        var parts: [String] = []

        if let ms = turn.durationMs {
            if ms < 1000 {
                parts.append("\(ms)ms")
            } else {
                let s = ms / 1000
                parts.append("\(s)s")
            }
        }

        if let usage = turn.usage {
            let total = usage.input + usage.output
            if total > 0 {
                if total >= 1000 {
                    let k = Double(total) / 1000.0
                    parts.append(String(format: "%.1fk tokens", k))
                } else {
                    parts.append("\(total) tokens")
                }
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

/// Streaming-safe markdown renderer in the serif agent voice.
struct MarkdownView: View {
    let text: String
    var isStreaming = false

    var body: some View {
        let blocks = ChatMarkdownParser.parse(text)

        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                let isLast = index == blocks.count - 1
                switch block {
                case .heading(let level, let headingText, _):
                    ChatHeadingView(level: level, text: headingText)
                case .paragraph(let paraText, _):
                    if isStreaming && isLast {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(ChatMarkdownParser.parseInline(paraText))
                                .font(Theme.serif(17))
                                .foregroundStyle(Theme.text)
                                .lineSpacing(5)
                            ChatBlinkingCaret()
                        }
                    } else {
                        Text(ChatMarkdownParser.parseInline(paraText))
                            .font(Theme.serif(17))
                            .foregroundStyle(Theme.text)
                            .lineSpacing(5)
                    }
                case .code(let lang, let codeText, _):
                    ChatCodeBlockView(language: lang, code: codeText)
                case .blockquote(let lines, _):
                    ChatBlockquoteView(lines: lines)
                case .list(let items, _):
                    ChatListView(items: items)
                case .table(let headers, let rows, _):
                    ChatTableView(headers: headers, rows: rows)
                case .horizontalRule:
                    Divider()
                        .overlay(Theme.hairline)
                        .padding(.vertical, 6)
                }
            }

            if isStreaming && (blocks.isEmpty || !isLastBlockParagraph(blocks)) {
                ChatBlinkingCaret()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Theme.link)
        .textSelection(.enabled)
    }

    private func isLastBlockParagraph(_ blocks: [ChatMarkdownBlock]) -> Bool {
        if case .paragraph = blocks.last {
            return true
        }
        return false
    }
}

/// Heading rendered in serif semibold with decreasing sizes.
struct ChatHeadingView: View {
    let level: Int
    let text: String

    var body: some View {
        let attr = ChatMarkdownParser.parseInline(text)
        switch level {
        case 1:
            Text(attr)
                .font(Theme.serif(26, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineSpacing(4)
                .padding(.top, 6)
        case 2:
            Text(attr)
                .font(Theme.serif(22, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineSpacing(4)
                .padding(.top, 4)
        case 3:
            Text(attr)
                .font(Theme.serif(19, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineSpacing(4)
                .padding(.top, 2)
        default:
            Text(attr)
                .font(Theme.serif(17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineSpacing(4)
        }
    }
}

/// Fenced code block: dark rounded box (#141413), header with language and Copy button,
/// mono(14) content, horizontal scrolling, and light keyword coloring.
struct ChatCodeBlockView: View {
    let language: String
    let code: String

    @Environment(UIState.self) private var ui
    @State private var isCopied = false

    private var displayLanguage: String {
        language.isEmpty ? "code" : language.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(displayLanguage)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.secondaryText)

                Spacer()

                Button {
                    copyCode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "square.on.square")
                            .font(Theme.sans(11))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(Theme.sans(12, weight: .medium))
                    }
                    .foregroundStyle(isCopied ? Theme.success : Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x19 / 255))

            Divider()
                .overlay(Theme.hairline)

            // Content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(ChatSyntaxHighlighter.highlight(code: code, language: displayLanguage))
                    .font(Theme.mono(14))
                    .lineSpacing(4)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .textSelection(.enabled)
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        ui.toast = "Copied"
        withAnimation(.snappy) {
            isCopied = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.snappy) {
                isCopied = false
            }
        }
    }
}

/// Tables: horizontal ScrollView grid with bold header row and hairline separators.
struct ChatTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                // Header row
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(ChatMarkdownParser.parseInline(header))
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .padding(.bottom, 4)
                    }
                }

                // Header separator
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, _ in
                        Divider()
                            .overlay(Theme.hairline)
                    }
                }

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(headers.indices), id: \.self) { colIndex in
                            let cellText = colIndex < row.count ? row[colIndex] : ""
                            Text(ChatMarkdownParser.parseInline(cellText))
                                .font(Theme.serif(15))
                                .foregroundStyle(Theme.text.opacity(0.9))
                        }
                    }

                    if rowIndex < rows.count - 1 {
                        GridRow {
                            ForEach(Array(headers.enumerated()), id: \.offset) { _, _ in
                                Divider()
                                    .overlay(Theme.hairline.opacity(0.5))
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}

/// Blockquote: left bar in Claude accent with serif quote text.
struct ChatBlockquoteView: View {
    let lines: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.accent.opacity(0.7))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(ChatMarkdownParser.parseInline(line))
                        .font(Theme.serif(16))
                        .foregroundStyle(Theme.text.opacity(0.85))
                        .lineSpacing(4)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 2)
    }
}

/// Bullet and numbered lists nested by indent with proper hanging indent.
struct ChatListView: View {
    let items: [ChatListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    switch item.kind {
                    case .bullet:
                        Text("•")
                            .font(Theme.sans(15, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 14, alignment: .trailing)
                    case .number(let numStr):
                        Text("\(numStr).")
                            .font(Theme.sans(14, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(minWidth: 20, alignment: .trailing)
                    }

                    Text(ChatMarkdownParser.parseInline(item.text))
                        .font(Theme.serif(17))
                        .foregroundStyle(Theme.text)
                        .lineSpacing(5)
                }
                .padding(.leading, CGFloat(item.level) * 18)
            }
        }
    }
}

/// Soft blinking dot caret appended while streaming agent responses.
struct ChatBlinkingCaret: View {
    @State private var isVisible = true

    var body: some View {
        Text("●")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.accent)
            .opacity(isVisible ? 1.0 : 0.2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
            .accessibilityHidden(true)
    }
}
