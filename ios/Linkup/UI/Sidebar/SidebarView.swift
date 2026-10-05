import SwiftUI

// MARK: - SidebarView

/// Claude-style drawer sidebar: agents, pinned sessions, recents grouped by date,
/// search, new session, and PC history import.
struct SidebarView: View {
    @Environment(SessionStore.self) private var store
    @Environment(LinkupClient.self) private var client
    @Environment(UIState.self) private var ui

    @State private var isSearching = false
    @State private var searchText = ""
    @State private var isShowingHistorySheet = false

    // State for renaming session
    @State private var sessionToRename: SessionInfo?
    @State private var renameTitle = ""
    @State private var isShowingRenameAlert = false

    // State for deleting session
    @State private var sessionToDelete: SessionInfo?
    @State private var isShowingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Header with search toggle
                headerSection

                // Search field (toggled via header search button)
                if isSearching {
                    searchBar
                }

                // 2. Top rows: Agents & From your PC
                agentRowsSection

                // Subtle hairline separator
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 4)

                // 3. Pinned & Recents sections
                sessionsSection

                // Space to scroll completely past the overlaid bottom bar
                Color.clear
                    .frame(height: 120)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            bottomOverlay
        }
        .sheet(isPresented: $isShowingHistorySheet) {
            HistoryImportSheet()
        }
        .alert("Rename Session", isPresented: $isShowingRenameAlert) {
            TextField("Session title", text: $renameTitle)
            Button("Save") {
                if let session = sessionToRename {
                    let trimmed = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        store.update(session.id, title: trimmed)
                    }
                }
                sessionToRename = nil
            }
            Button("Cancel", role: .cancel) {
                sessionToRename = nil
            }
        }
        .confirmationDialog("Delete Session?", isPresented: $isShowingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    store.delete(session.id)
                    if ui.currentSessionId == session.id {
                        ui.newChat()
                    }
                }
                sessionToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this session? This action cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            Text("Linkup")
                .font(Theme.serif(30, weight: .medium))
                .foregroundStyle(Theme.text)

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    isSearching.toggle()
                    if !isSearching {
                        searchText = ""
                    }
                }
            } label: {
                Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(isSearching ? "Close search" : "Search sessions")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)

            TextField("Search sessions…", text: $searchText)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Top Rows (Agents & PC)

    private var agentRowsSection: some View {
        VStack(spacing: 2) {
            ForEach(AgentKind.allCases, id: \.self) { kind in
                let agentId = kind.rawValue
                let isAvailable = store.agent(agentId)?.available == true

                Button {
                    ui.draftAgent = agentId
                    ui.draftModel = nil
                    ui.newChat()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Theme.text)
                            .frame(width: 28, height: 28, alignment: .center)

                        Text(kind.title)
                            .font(Theme.sans(19))
                            .foregroundStyle(Theme.text)

                        Spacer()

                        Circle()
                            .fill(isAvailable ? Theme.success : Color(white: 0.45))
                            .frame(width: 7, height: 7)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // From your PC row
            Button {
                isShowingHistorySheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.text)
                        .frame(width: 28, height: 28, alignment: .center)

                    Text("From your PC")
                        .font(Theme.sans(19))
                        .foregroundStyle(Theme.text)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sessions (Pinned & Recents)

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Pinned section
            if !pinnedSessions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pinned")
                        .font(Theme.sans(15, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 2)

                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(pinnedSessions) { session in
                            SidebarSessionRow(
                                session: session,
                                isSelected: ui.currentSessionId == session.id,
                                onSelect: {
                                    ui.currentSessionId = session.id
                                    ui.isSidebarOpen = false
                                },
                                onTogglePin: {
                                    store.update(session.id, pinned: !session.pinned)
                                },
                                onRename: {
                                    sessionToRename = session
                                    renameTitle = session.displayTitle
                                    isShowingRenameAlert = true
                                },
                                onDelete: {
                                    sessionToDelete = session
                                    isShowingDeleteConfirm = true
                                }
                            )
                        }
                    }
                }
            }

            // Recents section grouped by date
            ForEach(groupedRecents, id: \.0) { group, sessions in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.rawValue)
                        .font(Theme.sans(15, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 2)

                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(sessions) { session in
                            SidebarSessionRow(
                                session: session,
                                isSelected: ui.currentSessionId == session.id,
                                onSelect: {
                                    ui.currentSessionId = session.id
                                    ui.isSidebarOpen = false
                                },
                                onTogglePin: {
                                    store.update(session.id, pinned: !session.pinned)
                                },
                                onRename: {
                                    sessionToRename = session
                                    renameTitle = session.displayTitle
                                    isShowingRenameAlert = true
                                },
                                onDelete: {
                                    sessionToDelete = session
                                    isShowingDeleteConfirm = true
                                }
                            )
                        }
                    }
                }
            }

            // No matching results when searching
            if !searchText.isEmpty && filteredSessions.isEmpty {
                Text("No matching sessions")
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            }
        }
    }

    // MARK: - Filtered Sessions & Date Grouping

    private var filteredSessions: [SessionInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return store.sessions
        }
        return store.sessions.filter { s in
            s.displayTitle.localizedCaseInsensitiveContains(query) ||
            (s.preview ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var pinnedSessions: [SessionInfo] {
        filteredSessions.filter { $0.pinned }
    }

    private var recentSessions: [SessionInfo] {
        filteredSessions.filter { !$0.pinned }
    }

    private var groupedRecents: [(SidebarRecentsBucket, [SessionInfo])] {
        let recents = recentSessions
        guard !recents.isEmpty else { return [] }

        var dict: [SidebarRecentsBucket: [SessionInfo]] = [:]
        for bucket in SidebarRecentsBucket.allCases {
            dict[bucket] = []
        }

        let calendar = Calendar.current
        let now = Date()
        for session in recents {
            let b = bucket(for: session.updatedDate, now: now, calendar: calendar)
            dict[b]?.append(session)
        }

        return SidebarRecentsBucket.allCases.compactMap { bucket in
            guard let list = dict[bucket], !list.isEmpty else { return nil }
            return (bucket, list)
        }
    }

    private func bucket(for date: Date, now: Date, calendar: Calendar) -> SidebarRecentsBucket {
        if calendar.isDateInToday(date) || date > now {
            return .today
        }
        if calendar.isDateInYesterday(date) {
            return .yesterday
        }
        let startOfDate = calendar.startOfDay(for: date)
        let startOfNow = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 0
        if days <= 7 {
            return .previous7Days
        }
        return .older
    }

    // MARK: - Bottom Overlay

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Connection footer line
            connectionFooter

            // Bottom bar
            HStack(spacing: 12) {
                // Glass circle avatar with first letter of server name (or "L")
                Button {
                    ui.isShowingSettings = true
                } label: {
                    Text(avatarLetter)
                        .font(Theme.sans(17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Settings")

                // Big white capsule "+ New session"
                Button {
                    ui.newChat()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                        Text("New session")
                            .font(Theme.sans(18, weight: .medium))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New session")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background {
            LinearGradient(
                colors: [
                    Theme.background.opacity(0),
                    Theme.background.opacity(0.85),
                    Theme.background,
                    Theme.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var connectionFooter: some View {
        Button {
            if client.state != .connected && client.state != .connecting {
                client.connect()
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionDotColor)
                    .frame(width: 7, height: 7)

                Text(connectionStatusText)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var connectionDotColor: Color {
        switch client.state {
        case .connected:
            return Theme.success
        case .connecting:
            return Theme.accent
        case .offline:
            return Theme.danger
        case .notConfigured:
            return Theme.tertiaryText
        }
    }

    private var connectionStatusText: String {
        if client.state == .connected {
            if let latency = client.latencyMs {
                return "\(client.state.label) · \(latency) ms"
            }
            return client.state.label
        }
        return client.state.label
    }

    private var avatarLetter: String {
        if let name = client.serverName?.trimmingCharacters(in: .whitespacesAndNewlines),
           let first = name.first {
            return String(first).uppercased()
        }
        return "L"
    }
}

// MARK: - SidebarSessionRow

private struct SidebarSessionRow: View {
    let session: SessionInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isRevealed = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Trailing swipe action buttons (Pin & Delete)
            HStack(spacing: 4) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        dragOffset = 0
                        isRevealed = false
                    }
                    onTogglePin()
                } label: {
                    Image(systemName: session.pinned ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 38)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.pinned ? "Unpin session" : "Pin session")

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        dragOffset = 0
                        isRevealed = false
                    }
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 38)
                        .background(Theme.danger, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete session")
            }
            .opacity(dragOffset < -10 ? 1 : 0)

            // Main row button
            Button {
                if isRevealed {
                    withAnimation(.snappy(duration: 0.2)) {
                        dragOffset = 0
                        isRevealed = false
                    }
                } else {
                    onSelect()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: agentSymbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.agentColor(session.agent))
                        .frame(width: 22, height: 22)

                    Text(session.displayTitle)
                        .font(Theme.sans(18))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    if session.isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.secondaryText)
                    } else if session.hasUnread {
                        Circle()
                            .fill(Color(red: 0x3A / 255, green: 0x82 / 255, blue: 0xF7 / 255))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected ? Theme.elevated : (isRevealed ? Theme.surface : Color.clear),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .offset(x: dragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            let base: CGFloat = isRevealed ? -100 : 0
                            let translation = base + value.translation.width
                            dragOffset = min(0, max(-110, translation))
                        }
                    }
                    .onEnded { value in
                        withAnimation(.snappy(duration: 0.25)) {
                            if value.translation.width < -40 || (isRevealed && value.translation.width < 20) {
                                dragOffset = -100
                                isRevealed = true
                            } else {
                                dragOffset = 0
                                isRevealed = false
                            }
                        }
                    }
            )
        }
        .contextMenu {
            Button {
                onTogglePin()
            } label: {
                Label(session.pinned ? "Unpin" : "Pin", systemImage: session.pinned ? "pin.slash" : "pin")
            }

            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var agentSymbol: String {
        AgentKind(rawValue: session.agent)?.symbol ?? "asterisk"
    }
}

// MARK: - SidebarRecentsBucket

private enum SidebarRecentsBucket: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case previous7Days = "Previous 7 days"
    case older = "Older"

    var id: String { rawValue }
}

// MARK: - HistoryImportSheet

/// Presents Claude Code sessions started on the PC that can be continued on mobile.
struct HistoryImportSheet: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var items: [HistoryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var importingId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header: glass xmark close + centered title
            ZStack {
                Text("Continue from your PC")
                    .font(Theme.sans(18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Close")

                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            // Search field on top
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)

                TextField("Search PC sessions…", text: $searchText)
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Content: ProgressView, Inline Error, or Sessions List
            if isLoading && items.isEmpty {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)
                Spacer()
            } else if let error = errorMessage, items.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.danger)

                    Text(error)
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button("Try again") {
                        Task { await fetchHistory() }
                    }
                    .font(Theme.sans(15, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
                Spacer()
            } else if filteredItems.isEmpty {
                Spacer()
                Text(searchText.isEmpty ? "No PC sessions found" : "No matching sessions")
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
            } else {
                List {
                    // Inline error banner if refresh failed
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(Theme.danger)
                            Text(error)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.danger)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                    }

                    ForEach(filteredItems) { item in
                        Button {
                            importSession(item)
                        } label: {
                            SidebarHistoryItemRow(
                                item: item,
                                isImporting: importingId == item.id
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                        .listRowSeparatorTint(Theme.hairline)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationBackground(Theme.surface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await fetchHistory()
        }
    }

    private var filteredItems: [HistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return items }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(query) ||
            (item.cwd ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private func fetchHistory() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await store.loadHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func importSession(_ item: HistoryItem) {
        guard importingId == nil else { return }
        importingId = item.id
        Task {
            do {
                let s = try await store.importHistory(item)
                ui.currentSessionId = s.id
                ui.isSidebarOpen = false
                dismiss()
            } catch {
                ui.toast = error.localizedDescription
                errorMessage = error.localizedDescription
            }
            importingId = nil
        }
    }
}

// MARK: - SidebarHistoryItemRow

private struct SidebarHistoryItemRow: View {
    let item: HistoryItem
    let isImporting: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                // Title (2 lines)
                Text(item.title.isEmpty ? "Untitled Session" : item.title)
                    .font(Theme.sans(16, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Metadata: project folder name from cwd, relative date, message count
                HStack(spacing: 6) {
                    if let folder = projectFolder {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                        Text(folder)
                            .lineLimit(1)
                        Text("·")
                    }

                    Text(relativeDate)

                    if let count = item.messages {
                        Text("·")
                        Text("\(count) \(count == 1 ? "message" : "messages")")
                    }
                }
                .font(Theme.sans(13))
                .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 8)

            if isImporting {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .contentShape(Rectangle())
    }

    private var projectFolder: String? {
        guard let cwd = item.cwd, !cwd.isEmpty else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    private var relativeDate: String {
        let date = Date(timeIntervalSince1970: item.updated)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
