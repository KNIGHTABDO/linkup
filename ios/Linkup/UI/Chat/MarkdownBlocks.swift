import SwiftUI

/// Environment key for agent text serif font size (17 default, 18 in chat-mode).
private struct ChatTextSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 17
}

extension EnvironmentValues {
    var chatTextSize: CGFloat {
        get { self[ChatTextSizeKey.self] }
        set { self[ChatTextSizeKey.self] = newValue }
    }
}

/// Lays a user- or agent-written block out in its own direction (Arabic/Darija right-to-left, French/English
/// left-to-right) and aligns it to that direction's leading edge.
struct ChatTextDirection: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .environment(\.layoutDirection, text.dominantLayoutDirection)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func chatDirection(_ text: String) -> some View { modifier(ChatTextDirection(text: text)) }
}

private enum ChatCaret {
    /// The streaming caret as a text run, so it follows the last word in either direction.
    static func append(to attr: inout AttributedString) {
        var caret = AttributedString(" \u{25CF}")
        caret.foregroundColor = Theme.accent
        caret.font = Theme.sans(11, weight: .bold)
        attr.append(caret)
    }
}

/// Renders parsed markdown blocks. The caret (while streaming) is appended inside the last text block.
struct ChatBlocksView: View {
    let blocks: [ChatMarkdownBlock]
    var showCaret = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                ChatBlockView(block: block, showCaret: showCaret && index == blocks.count - 1 && block.carriesCaret)
            }
            if showCaret && !(blocks.last?.carriesCaret ?? false) {
                ChatBlinkingCaret()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Theme.link)
    }
}

extension ChatMarkdownBlock {
    /// Text blocks end with the inline streaming caret; code, tables, rules and images get a standalone one.
    var carriesCaret: Bool {
        switch self {
        case .heading, .paragraph, .blockquote, .list: true
        default: false
        }
    }
}

struct ChatBlockView: View {
    let block: ChatMarkdownBlock
    var showCaret = false

    var body: some View {
        switch block {
        case .heading(let level, let text, _):
            ChatHeadingView(level: level, text: text, showCaret: showCaret)
        case .paragraph(let text, _):
            ChatParagraphView(text: text, showCaret: showCaret)
        case .code(let lang, let code, _):
            ChatCodeBlockView(language: lang, code: code)
        case .blockquote(let lines, _):
            ChatBlockquoteView(lines: lines, showCaret: showCaret)
        case .list(let items, _):
            ChatListView(items: items, showCaret: showCaret)
        case .table(let headers, let rows, _):
            ChatTableView(headers: headers, rows: rows)
        case .horizontalRule:
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.vertical, 6)
        case .image(let alt, let url, _):
            ChatInlineImageView(alt: alt, url: url)
        }
    }
}

struct ChatParagraphView: View {
    let text: String
    var showCaret = false
    @Environment(\.chatTextSize) private var textSize: CGFloat

    var body: some View {
        var attr = ChatMarkdownParser.parseInline(text, codeSize: textSize - 2)
        if showCaret { ChatCaret.append(to: &attr) }
        return Text(attr)
            .font(Theme.serif(textSize))
            .foregroundStyle(Theme.text)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .chatDirection(text)
    }
}

/// Heading rendered in serif semibold with decreasing sizes (spacing comes from the block stack).
struct ChatHeadingView: View {
    let level: Int
    let text: String
    var showCaret = false
    @Environment(\.chatTextSize) private var textSize: CGFloat

    private var size: CGFloat {
        switch level {
        case 1: textSize + 9
        case 2: textSize + 5
        case 3: textSize + 2
        default: textSize
        }
    }

    var body: some View {
        var attr = ChatMarkdownParser.parseInline(text, codeSize: size - 3)
        if showCaret { ChatCaret.append(to: &attr) }
        return Text(attr)
            .font(Theme.serif(size, weight: .semibold))
            .foregroundStyle(Theme.text)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .chatDirection(text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Fenced code block: one dark surface, header with language and a 44pt Copy button, mono content that scrolls
/// horizontally. Highlighting runs off the main thread and is cached by (language, code).
struct ChatCodeBlockView: View {
    let language: String
    let code: String

    @Environment(UIState.self) private var ui
    @State private var isCopied = false
    @State private var copyReset: Task<Void, Never>?
    @State private var highlighted: AttributedString?
    @State private var highlightedSource = ""

    private var displayLanguage: String {
        language.isEmpty ? "code" : language.lowercased()
    }

    /// Highlighted text for the code, or while a fresh highlight is pending: the stale highlight plus the new tail.
    private var content: AttributedString {
        if let highlighted {
            if highlightedSource == code { return highlighted }
            if code.hasPrefix(highlightedSource) {
                var out = highlighted
                var rest = AttributedString(String(code.dropFirst(highlightedSource.count)))
                rest.foregroundColor = Theme.text
                out.append(rest)
                return out
            }
        }
        var plain = AttributedString(code)
        plain.foregroundColor = Theme.text
        return plain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(displayLanguage)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    copyCode()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isCopied ? "checkmark" : "square.on.square")
                            .font(Theme.sans(13))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(Theme.sans(13, weight: .medium))
                    }
                    .foregroundStyle(isCopied ? Theme.success : Theme.secondaryText)
                    .frame(minWidth: 84, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy code")
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(content)
                    .font(Theme.mono(14))
                    .lineSpacing(4)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .background(ChatPalette.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .task(id: code) { await refreshHighlight() }
    }

    private func refreshHighlight() async {
        let lang = displayLanguage
        let source = code
        if let hit = ChatSyntaxHighlighter.cachedValue(code: source, language: lang) {
            highlighted = hit
            highlightedSource = source
            return
        }
        // Debounce while the block is still streaming; a newer chunk cancels this task.
        try? await Task.sleep(nanoseconds: 70_000_000)
        if Task.isCancelled { return }
        let result = await Task.detached(priority: .userInitiated) {
            ChatSyntaxHighlighter.highlightCached(code: source, language: lang)
        }.value
        if Task.isCancelled { return }
        highlighted = result
        highlightedSource = source
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        ui.toast = "Copied"
        withAnimation(.snappy) { isCopied = true }
        copyReset?.cancel()
        copyReset = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            withAnimation(.snappy) { isCopied = false }
        }
    }
}

/// Tables: horizontally scrollable grid; cells wrap at a max width; direction follows the table's own text.
struct ChatTableView: View {
    let headers: [String]
    let rows: [[String]]
    @Environment(\.chatTextSize) private var textSize: CGFloat

    private var direction: LayoutDirection {
        (headers + (rows.first ?? [])).joined(separator: " ").dominantLayoutDirection
    }

    private func cell(_ text: String, header: Bool) -> some View {
        Text(ChatMarkdownParser.parseInline(text, codeSize: textSize - 4))
            .font(Theme.serif(textSize - 2, weight: header ? .semibold : .regular))
            .foregroundStyle(header ? Theme.text : Theme.text.opacity(0.9))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 240, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        cell(header, header: true)
                    }
                }

                GridRow {
                    ForEach(Array(headers.indices), id: \.self) { _ in
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(headers.indices), id: \.self) { colIndex in
                            cell(colIndex < row.count ? row[colIndex] : "", header: false)
                        }
                    }

                    if rowIndex < rows.count - 1 {
                        GridRow {
                            ForEach(Array(headers.indices), id: \.self) { _ in
                                Rectangle().fill(Theme.hairline.opacity(0.5)).frame(height: 1)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .environment(\.layoutDirection, direction)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}

/// Blockquote: accent bar on the leading edge of one continuous text.
struct ChatBlockquoteView: View {
    let lines: [String]
    var showCaret = false
    @Environment(\.chatTextSize) private var textSize: CGFloat

    var body: some View {
        let joined = lines.joined(separator: "\n")
        var attr = ChatMarkdownParser.parseInline(joined, codeSize: textSize - 3)
        if showCaret { ChatCaret.append(to: &attr) }
        return Text(attr)
            .font(Theme.serif(max(15, textSize - 1)))
            .foregroundStyle(Theme.text.opacity(0.85))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 15)
            .padding(.vertical, 2)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.accent.opacity(0.7))
                    .frame(width: 3)
            }
            .chatDirection(joined)
    }
}

/// Bullet, numbered and task lists: one marker column for all kinds, nesting by level, glyph varies by level.
struct ChatListView: View {
    let items: [ChatListItem]
    var showCaret = false
    @Environment(\.chatTextSize) private var textSize: CGFloat

    private static let bulletGlyphs = ["\u{2022}", "\u{25E6}", "\u{25AA}"]
    private let markerWidth: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item, caret: showCaret && index == items.count - 1)
            }
        }
    }

    private func row(_ item: ChatListItem, caret: Bool) -> some View {
        var attr = ChatMarkdownParser.parseInline(item.text, codeSize: textSize - 2)
        if caret { ChatCaret.append(to: &attr) }
        var struck = false
        if case .task(true) = item.kind { struck = true }

        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            marker(item)
                .frame(width: markerWidth, alignment: .trailing)

            Text(attr)
                .font(Theme.serif(textSize))
                .foregroundStyle(struck ? Theme.secondaryText : Theme.text)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(item.level) * 22)
        .environment(\.layoutDirection, item.text.dominantLayoutDirection)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func marker(_ item: ChatListItem) -> some View {
        switch item.kind {
        case .bullet:
            Text(Self.bulletGlyphs[min(item.level, Self.bulletGlyphs.count - 1)])
                .font(Theme.serif(textSize, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
        case .number(let n):
            Text("\(n).")
                .font(Theme.serif(textSize))
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
        case .task(let checked):
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: textSize - 2))
                .foregroundStyle(checked ? Theme.accent : Theme.secondaryText)
                .accessibilityLabel(checked ? "Done" : "Not done")
        }
    }
}

/// Standalone markdown image (`![alt](url)`).
struct ChatInlineImageView: View {
    let alt: String
    let url: String

    var body: some View {
        RemoteImageView(url: url)
            .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(alt.isEmpty ? "Image" : alt)
    }
}

/// Soft blinking dot, used before the first token of a reply arrives.
struct ChatBlinkingCaret: View {
    @State private var isVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\u{25CF}")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.accent)
            .opacity(isVisible ? 1.0 : 0.25)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
            .accessibilityHidden(true)
    }
}
