import SwiftUI

/// Classified slash command ready for card presentation.
struct CommandCardItem: Identifiable, Hashable {
    let id: String
    let rawName: String
    let cleanName: String
    let description: String?
    let kind: String
    let symbol: String
}

/// Floating sheet-like panel listing an agent's available slash commands as rich cards,
/// grouped by kind ("Commands", "Skills", "Plugins"), with search and recent chips.
struct CommandSuggestionsView: View {
    var agentId: String = "claude"
    let commands: [CommandInfo]
    let onSelect: (String) -> Void
    var onDismiss: (() -> Void)? = nil
    var initialQuery: String = ""

    @State private var searchQuery: String = ""
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        if UIDevice.current.userInterfaceIdiom == .pad || sizeClass == .regular {
            return [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        } else {
            return [GridItem(.flexible(), spacing: 10)]
        }
    }

    private var allItems: [CommandCardItem] {
        var seen = Set<String>()
        var items: [CommandCardItem] = []

        for cmd in commands {
            let clean = Self.cleanName(for: cmd)
            guard !clean.isEmpty else { continue }
            let lower = clean.lowercased()
            if seen.insert(lower).inserted {
                let kind = Self.classify(name: clean, description: cmd.description)
                let sym = Self.symbol(for: clean, description: cmd.description)
                items.append(CommandCardItem(
                    id: clean,
                    rawName: cmd.name ?? clean,
                    cleanName: clean,
                    description: cmd.description,
                    kind: kind,
                    symbol: sym
                ))
            }
        }
        return items
    }

    private var filteredItems: [CommandCardItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return allItems
        }
        let cleanQ = q.hasPrefix("/") ? String(q.dropFirst()) : q
        if cleanQ.isEmpty {
            return allItems
        }

        var prefixMatches: [CommandCardItem] = []
        var substringMatches: [CommandCardItem] = []

        for item in allItems {
            let name = item.cleanName.lowercased()
            let desc = (item.description ?? "").lowercased()
            if name.hasPrefix(cleanQ) {
                prefixMatches.append(item)
            } else if name.contains(cleanQ) || desc.contains(cleanQ) {
                substringMatches.append(item)
            }
        }
        return prefixMatches + substringMatches
    }

    private var groupedSections: [(kind: String, items: [CommandCardItem])] {
        let filtered = filteredItems
        let order = ["Commands", "Skills", "Plugins"]
        var grouped: [String: [CommandCardItem]] = [:]

        for item in filtered {
            grouped[item.kind, default: []].append(item)
        }

        var result: [(kind: String, items: [CommandCardItem])] = []
        for kind in order {
            if let list = grouped[kind], !list.isEmpty {
                result.append((kind: kind, items: list))
            }
        }
        // Any extra unexpected kinds
        for (kind, list) in grouped where !order.contains(kind) && !list.isEmpty {
            result.append((kind: kind, items: list))
        }
        return result
    }

    private var recentCommands: [CommandCardItem] {
        let recents = Self.loadRecentCommands(for: agentId)
        return recents.compactMap { name in
            allItems.first { $0.cleanName.lowercased() == name.lowercased() }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            searchBar

            if searchQuery.isEmpty && !recentCommands.isEmpty {
                recentChipsRow
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if groupedSections.isEmpty {
                        emptyView
                    } else {
                        ForEach(groupedSections, id: \.kind) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.kind)
                                    .font(Theme.sans(12, weight: .semibold))
                                    .foregroundStyle(Theme.secondaryText)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 4)

                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(section.items) { item in
                                        CommandCardView(command: item, agentId: agentId) {
                                            selectItem(item.cleanName)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .scrollDismissesKeyboard(.never)
        }
        .padding(.top, 14)
        .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.38), radius: 16, x: 0, y: 6)
        .onAppear {
            if !initialQuery.isEmpty {
                searchQuery = initialQuery
            }
        }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.secondaryText)

            TextField("Search commands\u{2026}", text: $searchQuery)
                .font(Theme.sans(15))
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.elevated))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 14)
    }

    private var recentChipsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(Theme.sans(11, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentCommands) { item in
                        Button {
                            selectItem(item.cleanName)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                                Text("/\(item.cleanName)")
                                    .font(Theme.sans(13, weight: .medium))
                                    .foregroundStyle(Theme.text)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.elevated, in: Capsule())
                            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "slash.circle")
                .font(.system(size: 28))
                .foregroundStyle(Theme.tertiaryText)
            Text("No matching commands")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func selectItem(_ cleanName: String) {
        Self.recordRecentCommand(cleanName, for: agentId)
        onSelect(cleanName)
    }

    // MARK: - Classification & Symbol Logic

    /// Classify command into kind:
    /// Names that look like plugin:skill -> "Plugins",
    /// names matching agent's known skills (contain "-" and long description) -> "Skills",
    /// others -> "Commands".
    static func classify(name: String, description: String?) -> String {
        if name.contains(":") {
            return "Plugins"
        }
        let descLen = description?.count ?? 0
        if name.contains("-") && descLen > 25 {
            return "Skills"
        }
        return "Commands"
    }

    /// Symbol picked by keywords:
    /// review→checkmark.seal, deploy→paperplane, test→testtube.2, design/ui→paintbrush,
    /// video→film, image→photo, ios→iphone, git/pr→arrow.triangle.branch, docs→doc.text, default→command.
    static func symbol(for name: String, description: String?) -> String {
        let text = "\(name) \(description ?? "")".lowercased()
        if text.contains("review") { return "checkmark.seal" }
        if text.contains("deploy") { return "paperplane" }
        if text.contains("test") { return "testtube.2" }
        if text.contains("design") || text.contains("ui") { return "paintbrush" }
        if text.contains("video") { return "film" }
        if text.contains("image") { return "photo" }
        if text.contains("ios") || text.contains("iphone") { return "iphone" }
        if text.contains("git") || text.contains("pr") { return "arrow.triangle.branch" }
        if text.contains("docs") || text.contains("doc") { return "doc.text" }
        return "command"
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

    // MARK: - Recents Persistence

    static func loadRecentCommands(for agentId: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: "recentCommands_\(agentId)") ?? []
    }

    static func recordRecentCommand(_ cleanName: String, for agentId: String) {
        var recents = loadRecentCommands(for: agentId)
        recents.removeAll { $0.lowercased() == cleanName.lowercased() }
        recents.insert(cleanName, at: 0)
        if recents.count > 10 {
            recents = Array(recents.prefix(10))
        }
        UserDefaults.standard.set(recents, forKey: "recentCommands_\(agentId)")
    }
}

/// A command card: rounded 16, Theme.elevated, leading 36pt tile with symbol picked by keywords,
/// the agent's AgentLogo small badge, "/name" semibold, description 2 lines secondary.
struct CommandCardView: View {
    let command: CommandCardItem
    let agentId: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.surface)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: command.symbol)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Theme.text)
                        }

                    AgentLogo(agent: agentId, size: 14)
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("/\(command.cleanName)")
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    if let desc = command.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                        Text(desc)
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(CommandCardButtonStyle())
    }
}

private struct CommandCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

typealias CommandSuggestions = CommandSuggestionsView
