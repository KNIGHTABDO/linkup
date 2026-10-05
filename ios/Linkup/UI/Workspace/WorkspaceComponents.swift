import Foundation
import SafariServices
import SwiftUI
import UIKit

// MARK: - Workspace Formatters

enum WorkspaceFormatters {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func relative(timestamp: Double?) -> String {
        guard let timestamp, timestamp > 0 else { return "" }
        let date = Date(timeIntervalSince1970: timestamp)
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return "just now"
        }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    static func fileSize(_ bytes: Int?) -> String {
        guard let bytes, bytes >= 0 else { return "" }
        return byteFormatter.string(fromByteCount: Int64(bytes))
    }

    static func pathTail(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Shorten home directories if possible
        var display = trimmed
        if let home = ProcessInfo.processInfo.environment["HOME"], display.hasPrefix(home) {
            display = "~" + display.dropFirst(home.count)
        } else if display.hasPrefix("/home/") {
            let parts = display.split(separator: "/", maxSplits: 3, omittingEmptySubsequences: true)
            if parts.count >= 2 {
                display = "~" + (parts.count > 2 ? "/" + parts[2...].joined(separator: "/") : "")
            }
        } else if display.hasPrefix("/Users/") {
            let parts = display.split(separator: "/", maxSplits: 3, omittingEmptySubsequences: true)
            if parts.count >= 2 {
                display = "~" + (parts.count > 2 ? "/" + parts[2...].joined(separator: "/") : "")
            }
        }

        let comps = display.split(separator: "/")
        if comps.count > 3 {
            return "…/" + comps.suffix(3).joined(separator: "/")
        }
        return display
    }

    static func fileIcon(for filename: String, isDir: Bool) -> String {
        if isDir { return "folder.fill" }
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        switch ext {
        case "swift":
            return "swift"
        case "py":
            return "curlybraces"
        case "js", "ts", "jsx", "tsx", "mjs", "cjs":
            return "curlybraces"
        case "html", "htm":
            return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "sass", "less":
            return "paintbrush"
        case "json", "yaml", "yml", "toml", "xml":
            return "doc.text"
        case "md", "markdown", "txt", "rtf":
            return "doc.plaintext"
        case "sh", "bash", "zsh":
            return "terminal"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "ico":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "zip", "tar", "gz", "bz2", "7z", "rar":
            return "archivebox"
        case "mp3", "wav", "m4a", "aac", "flac":
            return "waveform"
        case "mp4", "mov", "avi", "mkv", "webm":
            return "play.rectangle"
        default:
            return "doc"
        }
    }
}

// MARK: - Workspace Syntax Highlighter

enum WorkspaceLanguage {
    case swift
    case python
    case javascript
    case json
    case yaml
    case htmlCss
    case shell
    case plain

    static func detect(path: String, languageHint: String?) -> WorkspaceLanguage {
        if let hint = languageHint?.lowercased() {
            switch hint {
            case "swift": return .swift
            case "python", "py": return .python
            case "javascript", "typescript", "js", "ts", "jsx", "tsx": return .javascript
            case "json": return .json
            case "yaml", "yml": return .yaml
            case "html", "css", "htm": return .htmlCss
            case "sh", "bash", "zsh", "shell": return .shell
            default: break
            }
        }

        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "py", "pyw": return .python
        case "js", "ts", "jsx", "tsx", "mjs", "cjs": return .javascript
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "html", "htm", "css", "scss", "sass", "less": return .htmlCss
        case "sh", "bash", "zsh": return .shell
        default: return .plain
        }
    }
}

enum WorkspaceSyntaxHighlighter {
    private static let swiftKeywords: Set<String> = [
        "func", "var", "let", "class", "struct", "enum", "protocol", "extension", "import",
        "guard", "if", "else", "switch", "case", "default", "for", "while", "do", "in",
        "return", "try", "catch", "throw", "throws", "async", "await", "actor", "self",
        "init", "deinit", "public", "private", "internal", "fileprivate", "static", "mutating",
        "override", "weak", "unowned", "some", "any", "typealias", "where", "break", "continue",
        "fallthrough", "defer", "true", "false", "nil", "open"
    ]

    private static let pythonKeywords: Set<String> = [
        "def", "class", "import", "from", "as", "return", "if", "elif", "else", "for",
        "while", "try", "except", "finally", "raise", "with", "yield", "lambda", "pass",
        "break", "continue", "global", "nonlocal", "assert", "async", "await", "True",
        "False", "None", "self", "in", "is", "not", "and", "or", "match"
    ]

    private static let jsKeywords: Set<String> = [
        "function", "const", "let", "var", "class", "extends", "import", "export", "from",
        "default", "return", "if", "else", "switch", "case", "for", "while", "do", "try",
        "catch", "finally", "throw", "async", "await", "yield", "new", "this", "super",
        "interface", "type", "enum", "implements", "public", "private", "protected",
        "readonly", "static", "abstract", "true", "false", "null", "undefined", "typeof",
        "instanceof", "void", "delete", "in", "of"
    ]

    private static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until", "do",
        "done", "in", "function", "select", "time", "return", "exit", "echo", "export",
        "local", "alias", "source", "set", "unset", "test", "true", "false"
    ]

    private static let yamlJsonKeywords: Set<String> = [
        "true", "false", "null", "yes", "no", "on", "off"
    ]

    private static let htmlCssKeywords: Set<String> = [
        "color", "background", "margin", "padding", "border", "display", "flex", "grid",
        "width", "height", "font", "text", "position", "top", "bottom", "left", "right",
        "align", "justify", "none", "block", "inline", "auto", "relative", "absolute",
        "fixed", "import", "media", "keyframes"
    ]

    private static let keywordColor = Color(red: 0.96, green: 0.62, blue: 0.45)
    private static let stringColor = Color(red: 0.58, green: 0.82, blue: 0.62)
    private static let commentColor = Theme.tertiaryText
    private static let numberColor = Color(red: 0.72, green: 0.74, blue: 0.96)
    private static let typeColor = Color(red: 0.85, green: 0.78, blue: 0.52)

    static func highlight(line: String, language: WorkspaceLanguage) -> AttributedString {
        guard language != .plain, !line.isEmpty else {
            var plain = AttributedString(line)
            plain.foregroundColor = Theme.text
            return plain
        }

        let chars = Array(line)
        let n = chars.count
        var i = 0
        var result = AttributedString()

        while i < n {
            let ch = chars[i]

            // 1. Comments
            let isSlashComment = (ch == "/" && i + 1 < n && chars[i + 1] == "/")
            let isHashComment = (ch == "#" && (language == .python || language == .shell || language == .yaml))
            let isHtmlComment = (ch == "<" && i + 3 < n && chars[i + 1] == "!" && chars[i + 2] == "-" && chars[i + 3] == "-")

            if isSlashComment || isHashComment || isHtmlComment {
                var commentAttr = AttributedString(String(chars[i..<n]))
                commentAttr.foregroundColor = commentColor
                result.append(commentAttr)
                break
            }

            // 2. Strings: "...", '...', `...`
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
                    } else {
                        i += 1
                    }
                }
                var strAttr = AttributedString(String(chars[start..<i]))
                strAttr.foregroundColor = stringColor
                result.append(strAttr)
                continue
            }

            // 3. Numbers
            if ch.isNumber && (i == 0 || (!chars[i - 1].isLetter && chars[i - 1] != "_")) {
                let start = i
                while i < n && (chars[i].isNumber || chars[i] == "." || chars[i] == "x" || (chars[i] >= "a" && chars[i] <= "f") || (chars[i] >= "A" && chars[i] <= "F")) {
                    i += 1
                }
                var numAttr = AttributedString(String(chars[start..<i]))
                numAttr.foregroundColor = numberColor
                result.append(numAttr)
                continue
            }

            // 4. Identifiers, keywords, types
            if ch.isLetter || ch == "_" || ch == "$" || (ch == "-" && (language == .htmlCss || language == .shell)) {
                let start = i
                while i < n && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "$" || (chars[i] == "-" && (language == .htmlCss || language == .shell))) {
                    i += 1
                }
                let word = String(chars[start..<i])
                var wordAttr = AttributedString(word)

                if isKeyword(word, language: language) {
                    wordAttr.foregroundColor = keywordColor
                } else if word.first?.isUppercase == true && word.count > 1 {
                    wordAttr.foregroundColor = typeColor
                } else {
                    wordAttr.foregroundColor = Theme.text
                }
                result.append(wordAttr)
                continue
            }

            // 5. Symbols & whitespace
            let start = i
            while i < n {
                let c = chars[i]
                if c.isLetter || c.isNumber || c == "_" || c == "$" || c == "\"" || c == "'" || c == "`" ||
                    (c == "/" && i + 1 < n && chars[i + 1] == "/") ||
                    (c == "#" && (language == .python || language == .shell || language == .yaml)) ||
                    (c == "<" && i + 3 < n && chars[i + 1] == "!" && chars[i + 2] == "-" && chars[i + 3] == "-") {
                    break
                }
                i += 1
            }
            var symAttr = AttributedString(String(chars[start..<i]))
            symAttr.foregroundColor = Theme.text
            result.append(symAttr)
        }

        return result
    }

    private static func isKeyword(_ word: String, language: WorkspaceLanguage) -> Bool {
        let lower = word.lowercased()
        switch language {
        case .swift:
            return swiftKeywords.contains(word)
        case .python:
            return pythonKeywords.contains(word)
        case .javascript:
            return jsKeywords.contains(word)
        case .shell:
            return shellKeywords.contains(lower)
        case .json, .yaml:
            return yamlJsonKeywords.contains(lower)
        case .htmlCss:
            return htmlCssKeywords.contains(lower)
        case .plain:
            return false
        }
    }
}

// MARK: - Workspace Safari View

struct WorkspaceSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredBarTintColor = UIColor(red: 0x1F / 255, green: 0x1E / 255, blue: 0x1D / 255, alpha: 1)
        vc.preferredControlTintColor = UIColor(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Workspace Share Sheet

struct WorkspaceShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
