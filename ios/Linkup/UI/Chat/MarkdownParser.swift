import SwiftUI

/// A parsed markdown block suitable for streaming rendering in Chat.
enum ChatMarkdownBlock: Identifiable, Equatable {
    case heading(level: Int, text: String, id: String)
    case paragraph(text: String, id: String)
    case code(language: String, code: String, id: String)
    case blockquote(lines: [String], id: String)
    case list(items: [ChatListItem], id: String)
    case table(headers: [String], rows: [[String]], id: String)
    case horizontalRule(id: String)

    var id: String {
        switch self {
        case .heading(_, _, let id): id
        case .paragraph(_, let id): id
        case .code(_, _, let id): id
        case .blockquote(_, let id): id
        case .list(_, let id): id
        case .table(_, _, let id): id
        case .horizontalRule(let id): id
        }
    }
}

/// One list item with indentation depth and bullet/number indicator.
struct ChatListItem: Identifiable, Equatable {
    let id: String
    let level: Int
    let kind: ChatListKind
    let text: String
}

enum ChatListKind: Equatable {
    case bullet
    case number(String)
}

/// Cheap, streaming-safe markdown parser for the agent's voice.
/// Safely handles half-written fences, open quotes, partial lists, and unclosed tables.
enum ChatMarkdownParser {
    static func parse(_ markdown: String) -> [ChatMarkdownBlock] {
        guard !markdown.isEmpty else { return [] }

        var blocks: [ChatMarkdownBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var blockIdCounter = 0

        func nextId(_ prefix: String) -> String {
            blockIdCounter += 1
            return "\(prefix)_\(blockIdCounter)"
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // 1. Fenced Code Block: starts with ```
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let codeLine = lines[i]
                    let codeTrimmed = codeLine.trimmingCharacters(in: .whitespaces)
                    if codeTrimmed.hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(codeLine)
                    i += 1
                }
                blocks.append(.code(language: lang, code: codeLines.joined(separator: "\n"), id: nextId("code")))
                continue
            }

            // 2. Horizontal Rule: ---, ***, ___ (at least 3 characters)
            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule(id: nextId("hr")))
                i += 1
                continue
            }

            // 3. Heading: # ... ######
            if let heading = parseHeading(line) {
                blocks.append(.heading(level: heading.level, text: heading.text, id: nextId("h")))
                i += 1
                continue
            }

            // 4. Blockquote: lines starting with >
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let qLine = lines[i]
                    let qTrimmed = qLine.trimmingCharacters(in: .whitespaces)
                    if qTrimmed.hasPrefix(">") {
                        var content = qTrimmed.dropFirst()
                        if content.hasPrefix(" ") { content = content.dropFirst() }
                        quoteLines.append(String(content))
                        i += 1
                    } else if !qTrimmed.isEmpty && !quoteLines.isEmpty && !qTrimmed.hasPrefix("#") && !qTrimmed.hasPrefix("```") {
                        quoteLines.append(qTrimmed)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.blockquote(lines: quoteLines, id: nextId("quote")))
                continue
            }

            // 5. Table: check if current line has | and next line is separator
            if trimmed.contains("|") && i + 1 < lines.count && isTableSeparator(lines[i + 1]) {
                let headerRow = parseCells(line)
                i += 2 // skip header and separator
                var tableRows: [[String]] = []
                while i < lines.count {
                    let rLine = lines[i]
                    let rTrimmed = rLine.trimmingCharacters(in: .whitespaces)
                    guard !rTrimmed.isEmpty, rTrimmed.contains("|") else { break }
                    tableRows.append(parseCells(rLine))
                    i += 1
                }
                blocks.append(.table(headers: headerRow, rows: tableRows, id: nextId("tbl")))
                continue
            }

            // 6. List items: bullet or numbered
            if let firstItem = parseListItem(line) {
                var listItems: [ChatListItem] = [
                    ChatListItem(id: nextId("li"), level: firstItem.level, kind: firstItem.kind, text: firstItem.text)
                ]
                i += 1
                while i < lines.count {
                    let nextLine = lines[i]
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.isEmpty { break }

                    if let item = parseListItem(nextLine) {
                        listItems.append(ChatListItem(id: nextId("li"), level: item.level, kind: item.kind, text: item.text))
                        i += 1
                    } else if nextTrimmed.hasPrefix("```") || nextTrimmed.hasPrefix("#") || nextTrimmed.hasPrefix(">") {
                        break
                    } else {
                        // Continuation line of previous list item
                        if let last = listItems.last {
                            let updatedText = last.text + " " + nextTrimmed
                            listItems[listItems.count - 1] = ChatListItem(
                                id: last.id,
                                level: last.level,
                                kind: last.kind,
                                text: updatedText
                            )
                        }
                        i += 1
                    }
                }
                blocks.append(.list(items: listItems, id: nextId("list")))
                continue
            }

            // 7. Regular paragraph: gather lines until blank line or other block
            var paraLines: [String] = [line]
            i += 1
            while i < lines.count {
                let nextLine = lines[i]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty { break }
                if nextTrimmed.hasPrefix("```") || isHorizontalRule(nextTrimmed) || parseHeading(nextLine) != nil ||
                   nextTrimmed.hasPrefix(">") || (nextTrimmed.contains("|") && i + 1 < lines.count && isTableSeparator(lines[i + 1])) ||
                   parseListItem(nextLine) != nil {
                    break
                }
                paraLines.append(nextLine)
                i += 1
            }
            let paraText = paraLines.joined(separator: "\n")
            blocks.append(.paragraph(text: paraText, id: nextId("para")))
        }

        return blocks
    }

    /// Formats inline markdown (bold, italic, code, links, strike) with theme tinting.
    static func parseInline(_ text: String) -> AttributedString {
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
                attr[run.range].font = Theme.mono(15)
                attr[run.range].backgroundColor = Color.white.opacity(0.12)
            }
        }

        return attr
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let nonSpaces = trimmed.filter { !$0.isWhitespace }
        guard nonSpaces.count >= 3 else { return false }
        guard let first = nonSpaces.first, first == "-" || first == "*" || first == "_" else { return false }
        return nonSpaces.allSatisfy { $0 == first }
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1 && level <= 6 else { return nil }
        let remainder = line.dropFirst(level)
        guard remainder.hasPrefix(" ") else { return nil }
        let text = remainder.trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        let cells = parseCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmedCell = cell.trimmingCharacters(in: .whitespaces)
            return !trimmedCell.isEmpty && trimmedCell.allSatisfy { $0 == "-" || $0 == ":" } && trimmedCell.contains("-")
        }
    }

    private static func parseCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseListItem(_ line: String) -> (level: Int, kind: ChatListKind, text: String)? {
        var leadingSpaces = 0
        for ch in line {
            if ch == " " { leadingSpaces += 1 }
            else if ch == "\t" { leadingSpaces += 4 }
            else { break }
        }
        let level = min(leadingSpaces / 2, 4)
        let trimmed = String(line.dropFirst(leadingSpaces))

        // Bullet
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            let text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return (level, .bullet, text)
        }

        // Numbered: "1. ", "12. ", "1) "
        if let match = trimmed.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
            let numPrefix = String(trimmed[match]).trimmingCharacters(in: .whitespaces)
            let digits = numPrefix.filter(\.isNumber)
            let text = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (level, .number(digits), text)
        }

        return nil
    }
}

/// Fast single-pass syntax highlighter for common programming languages.
enum ChatSyntaxHighlighter {
    private static let keywords: Set<String> = [
        "func", "var", "let", "const", "def", "fn", "function", "class", "struct",
        "enum", "protocol", "extension", "import", "from", "as", "return", "if",
        "else", "elif", "switch", "case", "default", "for", "while", "do", "in",
        "of", "try", "catch", "throw", "throws", "async", "await", "true", "false",
        "nil", "null", "none", "self", "this", "super", "public", "private",
        "internal", "static", "typealias", "interface", "type", "package", "new",
        "yield", "break", "continue", "where", "guard", "mutating", "override"
    ]

    private static let types: Set<String> = [
        "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set",
        "Any", "Void", "Optional", "View", "Some", "Promise", "Error", "Date",
        "URL", "Data", "Task", "Color"
    ]

    static func highlight(code: String, language: String) -> AttributedString {
        var result = AttributedString()
        let chars = Array(code)
        var i = 0
        let n = chars.count

        let keywordColor = Color(red: 0.96, green: 0.62, blue: 0.45)
        let typeColor = Color(red: 0.85, green: 0.78, blue: 0.52)
        let stringColor = Color(red: 0.58, green: 0.82, blue: 0.62)
        let commentColor = Theme.tertiaryText
        let numberColor = Color(red: 0.72, green: 0.74, blue: 0.96)

        while i < n {
            let ch = chars[i]

            // Comment: // or #
            if (ch == "/" && i + 1 < n && chars[i + 1] == "/") || (ch == "#" && language != "c" && language != "cpp") {
                let start = i
                while i < n && chars[i] != "\n" {
                    i += 1
                }
                var attr = AttributedString(String(chars[start..<i]))
                attr.foregroundColor = commentColor
                result.append(attr)
                continue
            }

            // String: "..." or '...' or `...`
            if ch == "\"" || ch == "'" || ch == "`" {
                let quote = ch
                let start = i
                i += 1
                while i < n {
                    if chars[i] == "\\" && i + 1 < n {
                        i += 2
                    } else if chars[i] == quote {
                        i += 1
                        break
                    } else if chars[i] == "\n" && quote != "`" {
                        break
                    } else {
                        i += 1
                    }
                }
                var attr = AttributedString(String(chars[start..<i]))
                attr.foregroundColor = stringColor
                result.append(attr)
                continue
            }

            // Numbers
            if ch.isNumber && (i == 0 || (!chars[i - 1].isLetter && chars[i - 1] != "_")) {
                let start = i
                while i < n && (chars[i].isNumber || chars[i] == "." || chars[i] == "x" || (chars[i] >= "a" && chars[i] <= "f") || (chars[i] >= "A" && chars[i] <= "F")) {
                    i += 1
                }
                var attr = AttributedString(String(chars[start..<i]))
                attr.foregroundColor = numberColor
                result.append(attr)
                continue
            }

            // Words (keywords, types, identifiers)
            if ch.isLetter || ch == "_" || ch == "$" {
                let start = i
                while i < n && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    i += 1
                }
                let word = String(chars[start..<i])
                var attr = AttributedString(word)
                if keywords.contains(word.lowercased()) {
                    attr.foregroundColor = keywordColor
                } else if types.contains(word) || (word.first?.isUppercase == true && word.count > 1) {
                    attr.foregroundColor = typeColor
                } else {
                    attr.foregroundColor = Theme.text
                }
                result.append(attr)
                continue
            }

            // Whitespace and symbols
            let start = i
            while i < n {
                let c = chars[i]
                if c.isLetter || c.isNumber || c == "_" || c == "$" || c == "\"" || c == "'" || c == "`" || (c == "/" && i + 1 < n && chars[i + 1] == "/") || (c == "#") {
                    break
                }
                i += 1
            }
            var attr = AttributedString(String(chars[start..<i]))
            attr.foregroundColor = Theme.text
            result.append(attr)
        }

        return result
    }
}
