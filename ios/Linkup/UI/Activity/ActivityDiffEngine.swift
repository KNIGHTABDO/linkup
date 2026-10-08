import SwiftUI
import Foundation

// MARK: - Activity Diff Models & Engine

enum ActivityDiffKind: Hashable {
    case unchanged
    case deletion
    case addition
}

struct ActivityDiffLine: Identifiable, Hashable {
    let id: Int
    let kind: ActivityDiffKind
    let text: String
}

enum ActivityDiffEngine {
    /// Computes a line-by-line interleaved unified diff between old and new strings.
    static func diff(old: String, new: String, maxLines: Int = 800) -> [ActivityDiffLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        if old.isEmpty && new.isEmpty { return [] }
        if old.isEmpty {
            return newLines.enumerated().map { ActivityDiffLine(id: $0.offset, kind: .addition, text: $0.element) }
        }
        if new.isEmpty {
            return oldLines.enumerated().map { ActivityDiffLine(id: $0.offset, kind: .deletion, text: $0.element) }
        }

        let m = min(oldLines.count, maxLines)
        let n = min(newLines.count, maxLines)

        // DP table for Longest Common Subsequence (LCS)
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if oldLines[i - 1] == newLines[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack from bottom-right to build the interleaved diff
        var temp: [(ActivityDiffKind, String)] = []
        var i = m
        var j = n

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
                temp.append((.unchanged, oldLines[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                temp.append((.addition, newLines[j - 1]))
                j -= 1
            } else if i > 0 {
                temp.append((.deletion, oldLines[i - 1]))
                i -= 1
            }
        }

        temp.reverse()
        return temp.enumerated().map { idx, item in
            ActivityDiffLine(id: idx, kind: item.0, text: item.1)
        }
    }
}

// MARK: - Reusable Unified Diff View

struct ActivityUnifiedDiffView: View {
    let diffLines: [ActivityDiffLine]
    var maxDisplayLines: Int = 40

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(diffLines.prefix(maxDisplayLines)) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text(prefix(for: line.kind))
                            .font(Theme.mono(12, weight: .semibold))
                            .foregroundStyle(prefixColor(for: line.kind))
                            .frame(width: 14, alignment: .leading)

                        Text(line.text.isEmpty ? " " : line.text)
                            .font(Theme.mono(12))
                            .foregroundStyle(textColor(for: line.kind))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(backgroundColor(for: line.kind))
                }

                if diffLines.count > maxDisplayLines {
                    Text("+ \(diffLines.count - maxDisplayLines) more lines\u{2026}")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
            }
            .textSelection(.enabled)
        }
        .background(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.hairline, lineWidth: 1)
        }
    }

    private func prefix(for kind: ActivityDiffKind) -> String {
        switch kind {
        case .unchanged: return " "
        case .deletion: return "-"
        case .addition: return "+"
        }
    }

    private func prefixColor(for kind: ActivityDiffKind) -> Color {
        switch kind {
        case .unchanged: return Theme.tertiaryText
        case .deletion: return Theme.danger
        case .addition: return Theme.success
        }
    }

    private func textColor(for kind: ActivityDiffKind) -> Color {
        switch kind {
        case .unchanged: return Theme.secondaryText
        case .deletion: return Theme.danger
        case .addition: return Theme.success
        }
    }

    private func backgroundColor(for kind: ActivityDiffKind) -> Color {
        switch kind {
        case .unchanged: return Color.clear
        case .deletion: return Theme.danger.opacity(0.14)
        case .addition: return Theme.success.opacity(0.14)
        }
    }
}

// MARK: - Activity Helpers

enum ActivityHelpers {
    /// Humanized tool name for display in permission headers and activity rows.
    static func humanToolName(_ raw: String) -> String {
        let key = raw.lowercased()
        switch key {
        case "bash", "run_command", "terminal", "shell", "execute_code", "bashoutput":
            return "Bash"
        case "read", "view_file", "read_file", "notebookread":
            return "Read file"
        case "write", "write_to_file", "create_file":
            return "Create file"
        case "edit", "replace_file_content", "notebookedit":
            return "Edit file"
        case "multiedit", "multi_replace_file_content":
            return "Multi-edit"
        case "grep", "grep_search", "search_files":
            return "Search code"
        case "glob", "find_by_name", "list_dir", "ls":
            return "Find files"
        case "websearch", "search_web", "web_search":
            return "Web search"
        case "webfetch", "read_url_content", "fetch", "web_extract":
            return "Web fetch"
        case "task", "agent", "browser_subagent", "delegate_task":
            return "Sub-agent"
        case "todowrite", "update_plan", "todo":
            return "Update plan"
        case "generate_image", "image_generate", "create_image":
            return "Generate image"
        case "skill":
            return "Skill"
        case "memory", "recall":
            return "Memory"
        default:
            var name = raw
            if name.hasPrefix("mcp__") {
                name = String(name.dropFirst(5))
            }
            let cleaned = name.replacingOccurrences(of: "__", with: " ")
                .replacingOccurrences(of: "_", with: " ")
            return cleaned.capitalized
        }
    }

    /// Safely extracts a string field from streaming partial JSON if complete JSON hasn't arrived.
    static func extractPartialString(from partialJSON: String?, keys: [String]) -> String? {
        guard let partial = partialJSON, !partial.isEmpty else { return nil }
        for key in keys {
            let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]*)\""
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsString = partial as NSString
                if let match = regex.firstMatch(in: partial, options: [], range: NSRange(location: 0, length: nsString.length)),
                   match.numberOfRanges > 1 {
                    let range = match.range(at: 1)
                    if range.location != NSNotFound {
                        let extracted = nsString.substring(with: range)
                            .replacingOccurrences(of: "\\n", with: "\n")
                            .replacingOccurrences(of: "\\\"", with: "\"")
                            .replacingOccurrences(of: "\\\\", with: "\\")
                        if !extracted.isEmpty {
                            return extracted
                        }
                    }
                }
            }
        }
        return nil
    }
}
