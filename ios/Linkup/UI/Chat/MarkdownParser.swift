import SwiftUI

/// A parsed markdown block suitable for streaming rendering in Chat.
/// Ids are positional ("para_3"), so a block keeps its identity while the text after it keeps growing.
enum ChatMarkdownBlock: Identifiable, Equatable {
    case heading(level: Int, text: String, id: String)
    case paragraph(text: String, id: String)
    case code(language: String, code: String, id: String)
    case blockquote(lines: [String], id: String)
    case list(items: [ChatListItem], id: String)
    case table(headers: [String], rows: [[String]], id: String)
    case horizontalRule(id: String)
    case image(alt: String, url: String, id: String)

    var id: String {
        switch self {
        case .heading(_, _, let id): id
        case .paragraph(_, let id): id
        case .code(_, _, let id): id
        case .blockquote(_, let id): id
        case .list(_, let id): id
        case .table(_, _, let id): id
        case .horizontalRule(let id): id
        case .image(_, _, let id): id
        }
    }
}

/// One list item with nesting level and bullet/number/checkbox indicator.
struct ChatListItem: Identifiable, Equatable {
    let id: String
    let level: Int
    let kind: ChatListKind
    let text: String
}

enum ChatListKind: Equatable {
    case bullet
    case number(String)
    /// `- [ ]` / `- [x]`
    case task(Bool)
}

/// Colours of code surfaces (no Theme token exists for them).
enum ChatPalette {
    static let codeBackground = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x16 / 255)
}

private final class ChatCacheBox<T> {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Cheap, streaming-safe markdown parser for the agent's voice.
/// Safely handles half-written fences, open quotes, partial lists, and unclosed tables.
enum ChatMarkdownParser {
    private static let blockCache: NSCache<NSString, ChatCacheBox<[ChatMarkdownBlock]>> = {
        let c = NSCache<NSString, ChatCacheBox<[ChatMarkdownBlock]>>()
        c.countLimit = 400
        return c
    }()
    private static let inlineCache: NSCache<NSString, ChatCacheBox<AttributedString>> = {
        let c = NSCache<NSString, ChatCacheBox<AttributedString>>()
        c.countLimit = 1500
        return c
    }()
    private static let imageRegex = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(\s*(\S+?)(?:\s+"[^"]*")?\s*\)$"#)

    /// `parse` with a result cache keyed by the exact text (finished messages are re-rendered on every scroll).
    static func parseCached(_ markdown: String, streaming: Bool = false) -> [ChatMarkdownBlock] {
        let key = ((streaming ? "s" : "f") + markdown) as NSString
        if let hit = blockCache.object(forKey: key) { return hit.value }
        let blocks = parse(markdown, streaming: streaming)
        blockCache.setObject(ChatCacheBox(blocks), forKey: key, cost: markdown.utf8.count)
        return blocks
    }

    static func parse(_ markdown: String, streaming: Bool = false) -> [ChatMarkdownBlock] {
        guard !markdown.isEmpty else { return [] }

        var blocks: [ChatMarkdownBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // 1. Fenced code block: ``` or ~~~ (a closing fence is only fence characters, at least as long)
            if let fence = openingFence(trimmed) {
                // The info string may still be arriving: show the language badge only once the line is complete.
                let lang = i == lines.count - 1 ? "" : fence.info
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let codeLine = lines[i]
                    if isClosingFence(codeLine.trimmingCharacters(in: .whitespaces), char: fence.char, length: fence.length) {
                        i += 1
                        break
                    }
                    codeLines.append(codeLine)
                    i += 1
                }
                blocks.append(.code(language: lang, code: codeLines.joined(separator: "\n"), id: "code_\(blocks.count)"))
                continue
            }

            // 2. Horizontal rule
            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule(id: "hr_\(blocks.count)"))
                i += 1
                continue
            }

            // 3. Heading
            if let heading = parseHeading(trimmed, rawLine: line) {
                blocks.append(.heading(level: heading.level, text: heading.text, id: "h_\(blocks.count)"))
                i += 1
                continue
            }

            // 4. Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let qTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if qTrimmed.hasPrefix(">") {
                        var content = qTrimmed.dropFirst()
                        if content.hasPrefix(" ") { content = content.dropFirst() }
                        quoteLines.append(String(content))
                        i += 1
                    } else if !qTrimmed.isEmpty && !quoteLines.isEmpty && !startsBlock(qTrimmed) {
                        quoteLines.append(qTrimmed)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.blockquote(lines: quoteLines, id: "quote_\(blocks.count)"))
                continue
            }

            // 5. Table: header row, then a separator row
            if trimmed.contains("|") && i + 1 < lines.count && isTableSeparator(lines[i + 1]) {
                let headerRow = parseCells(line)
                i += 2
                var tableRows: [[String]] = []
                while i < lines.count {
                    let rTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !rTrimmed.isEmpty, rTrimmed.contains("|") else { break }
                    tableRows.append(parseCells(lines[i]))
                    i += 1
                }
                blocks.append(.table(headers: headerRow, rows: tableRows, id: "tbl_\(blocks.count)"))
                continue
            }
            // A header row still waiting for its separator while streaming: show the table already, not raw pipes.
            if streaming, i == lines.count - 1, trimmed.hasPrefix("|"), trimmed.filter({ $0 == "|" }).count >= 2 {
                blocks.append(.table(headers: parseCells(line), rows: [], id: "tbl_\(blocks.count)"))
                i += 1
                continue
            }

            // 6. List (bullets, numbers, tasks; nested by indentation; continues across blank lines)
            if parseListItem(line) != nil {
                let listIndex = blocks.count
                var items: [ChatListItem] = []
                var indentStack: [Int] = []

                func level(for indent: Int) -> Int {
                    while let top = indentStack.last, indent < top { indentStack.removeLast() }
                    if indentStack.isEmpty || indent >= indentStack[indentStack.count - 1] + 2 {
                        indentStack.append(indent)
                    }
                    return min(indentStack.count - 1, 5)
                }
                func appendToLast(_ extra: String, separator: String) {
                    guard let last = items.last else { return }
                    items[items.count - 1] = ChatListItem(id: last.id, level: last.level, kind: last.kind,
                                                          text: last.text + separator + extra)
                }

                while i < lines.count {
                    let nextLine = lines[i]
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)

                    if nextTrimmed.isEmpty {
                        // Loose list: keep going if the next non-blank line is an item or an indented continuation.
                        var j = i
                        while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                        guard j < lines.count else { i = j; break }
                        let peek = lines[j]
                        if parseListItem(peek) != nil {
                            i = j
                            continue
                        }
                        let peekTrimmed = peek.trimmingCharacters(in: .whitespaces)
                        if leadingSpaces(peek) >= 2, !startsBlock(peekTrimmed), !items.isEmpty {
                            appendToLast(peekTrimmed, separator: "\n\n")
                            i = j + 1
                            continue
                        }
                        i = j
                        break
                    }

                    if let item = parseListItem(nextLine) {
                        items.append(ChatListItem(id: "li_\(listIndex)_\(items.count)", level: level(for: item.indent),
                                                  kind: item.kind, text: item.text))
                        i += 1
                    } else if startsBlock(nextTrimmed) {
                        break
                    } else {
                        appendToLast(nextTrimmed, separator: "\n")
                        i += 1
                    }
                }
                blocks.append(.list(items: items, id: "list_\(listIndex)"))
                continue
            }

            // 7. Paragraph: gather lines until blank line or another block starts
            var paraLines: [String] = [line]
            i += 1
            while i < lines.count {
                let nextLine = lines[i]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty { break }
                if startsBlock(nextTrimmed) || isHorizontalRule(nextTrimmed) || parseListItem(nextLine) != nil ||
                   (nextTrimmed.contains("|") && i + 1 < lines.count && isTableSeparator(lines[i + 1])) {
                    break
                }
                paraLines.append(nextLine)
                i += 1
            }
            if paraLines.count == 1, let img = parseImage(trimmed) {
                blocks.append(.image(alt: img.alt, url: img.url, id: "img_\(blocks.count)"))
            } else {
                blocks.append(.paragraph(text: paraLines.joined(separator: "\n"), id: "para_\(blocks.count)"))
            }
        }

        return blocks
    }

    /// Formats inline markdown (bold, italic, code, links, strike) with theme tinting. Cached by text.
    static func parseInline(_ text: String, codeSize: CGFloat = 15) -> AttributedString {
        let key = "\(Int(codeSize))|\(text)" as NSString
        if let hit = inlineCache.object(forKey: key) { return hit.value }

        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace

        var attr: AttributedString
        do {
            attr = try AttributedString(markdown: text, options: options)
        } catch {
            attr = AttributedString(text)
        }

        for run in attr.runs {
            if run.link != nil {
                attr[run.range].foregroundColor = Theme.link
            }
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                attr[run.range].font = Theme.mono(codeSize)
                attr[run.range].backgroundColor = Theme.elevated
            }
        }

        inlineCache.setObject(ChatCacheBox(attr), forKey: key, cost: text.utf8.count * 8)
        return attr
    }

    /// Plain text of inline markdown (markers removed): PDF export, accessibility.
    static func plainInline(_ text: String) -> String {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attr = try? AttributedString(markdown: text, options: options) {
            return String(attr.characters)
        }
        return text
    }

    // MARK: Line classification

    private static func leadingSpaces(_ line: String) -> Int {
        var n = 0
        for ch in line {
            if ch == " " { n += 1 } else if ch == "\t" { n += 4 } else { break }
        }
        return n
    }

    /// Lines that end a paragraph / list item continuation.
    private static func startsBlock(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") || trimmed.hasPrefix(">") ||
            trimmed.hasPrefix("#") && parseHeading(trimmed, rawLine: trimmed) != nil
    }

    private static func openingFence(_ trimmed: String) -> (char: Character, length: Int, info: String)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let length = trimmed.prefix { $0 == first }.count
        guard length >= 3 else { return nil }
        let rest = trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces)
        // A backtick fence's info string cannot contain backticks (that would be inline code).
        if first == "`" && rest.contains("`") { return nil }
        let info = rest.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        return (first, length, info)
    }

    private static func isClosingFence(_ trimmed: String, char: Character, length: Int) -> Bool {
        guard trimmed.count >= length else { return false }
        return trimmed.allSatisfy { $0 == char }
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let nonSpaces = trimmed.filter { !$0.isWhitespace }
        guard nonSpaces.count >= 3 else { return false }
        guard let first = nonSpaces.first, first == "-" || first == "*" || first == "_" else { return false }
        return nonSpaces.allSatisfy { $0 == first }
    }

    private static func parseHeading(_ trimmed: String, rawLine: String) -> (level: Int, text: String)? {
        guard leadingSpaces(rawLine) <= 3 else { return nil }
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1 && level <= 6 else { return nil }
        let remainder = trimmed.dropFirst(level)
        guard remainder.hasPrefix(" ") else { return nil }
        var text = remainder.trimmingCharacters(in: .whitespaces)
        // Closing sequence: "## Title ##"
        while text.hasSuffix("#") { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func parseImage(_ trimmed: String) -> (alt: String, url: String)? {
        guard trimmed.hasPrefix("!["), let regex = imageRegex else { return nil }
        let ns = trimmed as NSString
        guard let m = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges >= 3 else { return nil }
        return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") || trimmed.contains("-") else { return false }
        guard trimmed.contains("|") else { return false }
        let cells = parseCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" } && c.contains("-")
        }
    }

    /// Splits a table row on unescaped pipes that are not inside inline code; `\|` becomes a literal pipe.
    private static func parseCells(_ line: String) -> [String] {
        var chars = Array(line.trimmingCharacters(in: .whitespaces))
        if chars.first == "|" { chars.removeFirst() }
        if chars.last == "|", !(chars.count >= 2 && chars[chars.count - 2] == "\\") { chars.removeLast() }

        var cells: [String] = []
        var current = ""
        var inCode = false
        var k = 0
        while k < chars.count {
            let c = chars[k]
            if c == "\\", k + 1 < chars.count, chars[k + 1] == "|" {
                current.append("|")
                k += 2
                continue
            }
            if c == "`" { inCode.toggle() }
            if c == "|" && !inCode {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(c)
            }
            k += 1
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func parseListItem(_ line: String) -> (indent: Int, kind: ChatListKind, text: String)? {
        let indent = leadingSpaces(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Bullet (a bare "---" is a rule, handled before this)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            var text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            for (marker, checked) in [("[ ]", false), ("[x]", true), ("[X]", true)] where text.hasPrefix(marker + " ") || text == marker {
                text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                return (indent, .task(checked), text)
            }
            return (indent, .bullet, text)
        }

        // Numbered: "1. ", "12. ", "1) " (at most 3 digits, so "2024. It was" stays a sentence)
        var digits = ""
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex, let d = trimmed[idx].wholeNumberValue, trimmed[idx].isNumber, digits.count < 4 {
            digits += String(d)
            idx = trimmed.index(after: idx)
        }
        guard !digits.isEmpty, digits.count <= 3, idx < trimmed.endIndex,
              trimmed[idx] == "." || trimmed[idx] == ")" else { return nil }
        let afterMarker = trimmed.index(after: idx)
        guard afterMarker < trimmed.endIndex, trimmed[afterMarker] == " " else { return nil }
        let text = String(trimmed[afterMarker...]).trimmingCharacters(in: .whitespaces)
        return (indent, .number(digits), text)
    }
}

/// Fast single-pass syntax highlighter for common programming languages.
/// Every iteration consumes at least one character; strings never run past their line (so a quote that is still
/// streaming in cannot colour the rest of the block); very large blocks stay uncoloured.
enum ChatSyntaxHighlighter {
    private enum Kind { case plain, keyword, type, string, comment, number }

    private static let cache: NSCache<NSString, ChatCacheBox<AttributedString>> = {
        let c = NSCache<NSString, ChatCacheBox<AttributedString>>()
        c.countLimit = 120
        return c
    }()

    static let maxHighlightedCharacters = 24_000

    private static let keywords: Set<String> = [
        "func", "var", "let", "const", "def", "fn", "function", "class", "struct",
        "enum", "protocol", "extension", "import", "from", "as", "return", "if",
        "else", "elif", "switch", "case", "default", "for", "while", "do", "in",
        "of", "try", "catch", "throw", "throws", "async", "await", "true", "false",
        "nil", "null", "none", "self", "this", "super", "public", "private",
        "internal", "static", "typealias", "interface", "type", "package", "new",
        "yield", "break", "continue", "where", "guard", "mutating", "override",
        "then", "fi", "esac", "done", "echo", "export", "local", "with", "pass", "lambda"
    ]

    private static let types: Set<String> = [
        "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set",
        "Any", "Void", "Optional", "View", "Some", "Promise", "Error", "Date",
        "URL", "Data", "Task", "Color"
    ]

    /// Languages whose line comments start with `#`.
    private static let hashLanguages: Set<String> = [
        "python", "py", "sh", "bash", "shell", "zsh", "fish", "ruby", "rb", "yaml", "yml", "toml", "perl", "pl", "r",
        "makefile", "make", "dockerfile", "ini", "conf", "powershell", "ps1", "elixir", "nim", "env", "properties", "gitignore"
    ]
    private static let dashCommentLanguages: Set<String> = ["sql", "lua", "haskell", "hs"]
    private static let noSlashLanguages: Set<String> = [
        "html", "xml", "markdown", "md", "text", "txt", "plaintext", "json"
    ]

    static func highlightCached(code: String, language: String) -> AttributedString {
        let key = (language + "\u{1}" + code) as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        let result = highlight(code: code, language: language)
        cache.setObject(ChatCacheBox(result), forKey: key, cost: code.utf8.count * 12)
        return result
    }

    static func cachedValue(code: String, language: String) -> AttributedString? {
        cache.object(forKey: (language + "\u{1}" + code) as NSString)?.value
    }

    static func highlight(code: String, language: String) -> AttributedString {
        let lang = language.lowercased()
        let chars = Array(code)
        let n = chars.count

        guard n <= maxHighlightedCharacters else {
            var plain = AttributedString(code)
            plain.foregroundColor = Theme.text
            return plain
        }

        let hashComments = hashLanguages.contains(lang)
        let slashComments = !hashComments && !noSlashLanguages.contains(lang) && !dashCommentLanguages.contains(lang)
        let dashComments = dashCommentLanguages.contains(lang)
        let blockComments = !hashComments && !noSlashLanguages.contains(lang)

        // (start, end, kind) spans, merged when neighbours share a kind
        var spans: [(Int, Int, Kind)] = []
        func emit(_ s: Int, _ e: Int, _ k: Kind) {
            guard e > s else { return }
            if let last = spans.last, last.2 == k, last.1 == s {
                spans[spans.count - 1].1 = e
            } else {
                spans.append((s, e, k))
            }
        }
        func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        func endOfLine(from i: Int) -> Int {
            var j = i
            while j < n && chars[j] != "\n" { j += 1 }
            return j
        }

        var i = 0
        while i < n {
            let start = i
            let ch = chars[i]
            let next: Character? = i + 1 < n ? chars[i + 1] : nil
            var end = i + 1
            var kind: Kind = .plain

            if slashComments && ch == "/" && next == "/" {
                end = endOfLine(from: i)
                kind = .comment
            } else if blockComments && ch == "/" && next == "*" {
                var j = i + 2
                while j + 1 < n && !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                end = j + 1 < n ? j + 2 : n
                kind = .comment
            } else if hashComments && ch == "#" && (i == 0 || chars[i - 1].isWhitespace) {
                end = endOfLine(from: i)
                kind = .comment
            } else if dashComments && ch == "-" && next == "-" {
                end = endOfLine(from: i)
                kind = .comment
            } else if ch == "\"" || ch == "'" || ch == "`" {
                let quote = ch
                kind = .string
                if lang.hasPrefix("py"), i + 2 < n, chars[i + 1] == quote, chars[i + 2] == quote, quote != "`" {
                    var j = i + 3
                    while j + 2 < n && !(chars[j] == quote && chars[j + 1] == quote && chars[j + 2] == quote) { j += 1 }
                    end = j + 2 < n ? j + 3 : n
                } else if quote == "`" {
                    var j = i + 1
                    while j < n && chars[j] != "`" { j += 1 }
                    // No closing backtick yet (still streaming): colour this line only.
                    end = j < n ? j + 1 : max(endOfLine(from: i), i + 1)
                } else {
                    var j = i + 1
                    var closed = false
                    while j < n {
                        if chars[j] == "\\" && j + 1 < n && chars[j + 1] != "\n" {
                            j += 2
                        } else if chars[j] == quote {
                            j += 1
                            closed = true
                            break
                        } else if chars[j] == "\n" {
                            break
                        } else {
                            j += 1
                        }
                    }
                    end = closed ? j : max(min(j, n), i + 1)
                }
            } else if ch.isNumber && (i == 0 || !(isWordChar(chars[i - 1]) || chars[i - 1] == "$")) {
                var j = i + 1
                if ch == "0", let x = next, x == "x" || x == "X" || x == "b" || x == "B" {
                    j = i + 2
                    while j < n && (chars[j].isHexDigit || chars[j] == "_") { j += 1 }
                } else {
                    while j < n {
                        let c = chars[j]
                        if c.isNumber || c == "_" {
                            j += 1
                        } else if c == ".", j + 1 < n, chars[j + 1].isNumber {
                            j += 1
                        } else if (c == "e" || c == "E"), j + 1 < n, chars[j + 1].isNumber || chars[j + 1] == "-" || chars[j + 1] == "+" {
                            j += 2
                        } else {
                            break
                        }
                    }
                }
                end = max(j, i + 1)
                kind = .number
            } else if ch.isLetter || ch == "_" || (ch == "$" && next.map { $0.isLetter || $0 == "_" } == true) {
                // `$name` (shell/PHP variables) is one plain word; a lone `$` falls through to the symbol branch.
                var j = i + 1
                while j < n && isWordChar(chars[j]) { j += 1 }
                end = max(j, i + 1)
                if ch != "$" {
                    let word = String(chars[i..<end])
                    if keywords.contains(word.lowercased()) {
                        kind = .keyword
                    } else if types.contains(word) || (word.first?.isUppercase == true && word.count > 1) {
                        kind = .type
                    }
                }
            }
            // else: whitespace / symbol: exactly one plain character.

            if end <= start { end = start + 1 }
            emit(start, min(end, n), kind)
            i = min(end, n)
        }

        var result = AttributedString()
        for (s, e, k) in spans {
            var piece = AttributedString(String(chars[s..<e]))
            switch k {
            case .plain: piece.foregroundColor = Theme.text
            case .keyword: piece.foregroundColor = Color(red: 0.96, green: 0.62, blue: 0.45)
            case .type: piece.foregroundColor = Color(red: 0.85, green: 0.78, blue: 0.52)
            case .string: piece.foregroundColor = Color(red: 0.58, green: 0.82, blue: 0.62)
            case .comment: piece.foregroundColor = Theme.tertiaryText
            case .number: piece.foregroundColor = Color(red: 0.72, green: 0.74, blue: 0.96)
            }
            result.append(piece)
        }
        return result
    }
}
