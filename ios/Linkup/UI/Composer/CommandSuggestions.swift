import SwiftUI

/// Floating autocomplete panel listing an agent's available slash commands.
struct CommandSuggestionsView: View {
    let commands: [CommandInfo]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(commands.enumerated()), id: \.offset) { index, command in
                    let clean = Self.cleanName(for: command)
                    Button {
                        onSelect(clean)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("/\(clean)")
                                    .font(Theme.sans(16, weight: .medium))
                                    .foregroundStyle(Theme.text)

                                if let desc = command.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                                    Text(desc)
                                        .font(Theme.sans(13))
                                        .foregroundStyle(Theme.secondaryText)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CommandRowButtonStyle())

                    if index < commands.count - 1 {
                        Divider()
                            .overlay(Theme.hairline)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.never)
        .frame(maxHeight: 300)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 4)
    }

    /// Strips any leading slash or extraneous whitespace from a command's raw name.
    static func cleanName(for command: CommandInfo) -> String {
        guard let raw = command.name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }
        return raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
    }

    /// Filters and sorts commands matching the typed prefix (case-insensitive, prefix first, then substring), max 50 rows.
    static func filter(commands: [CommandInfo]?, text: String) -> [CommandInfo] {
        guard text.hasPrefix("/"), !text.contains(" "), !text.contains("\n") else {
            return []
        }
        guard let commands, !commands.isEmpty else {
            return []
        }

        var seen = Set<String>()
        var valid: [(cmd: CommandInfo, clean: String)] = []
        for cmd in commands {
            let clean = cleanName(for: cmd)
            guard !clean.isEmpty else { continue }
            let lower = clean.lowercased()
            if seen.insert(lower).inserted {
                valid.append((cmd, clean))
            }
        }

        let query = String(text.dropFirst()).lowercased()

        if query.isEmpty {
            return Array(valid.map(\.cmd).prefix(50))
        }

        var prefixMatches: [CommandInfo] = []
        var substringMatches: [CommandInfo] = []

        for item in valid {
            let lower = item.clean.lowercased()
            if lower.hasPrefix(query) {
                prefixMatches.append(item.cmd)
            } else if lower.contains(query) {
                substringMatches.append(item.cmd)
            }
        }

        return Array((prefixMatches + substringMatches).prefix(50))
    }
}

typealias CommandSuggestions = CommandSuggestionsView

private struct CommandRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.elevated : Color.clear)
    }
}
