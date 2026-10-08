import SwiftUI

// MARK: - SidebarView

/// Claude-style drawer sidebar: agents, pinned sessions, recents grouped by date,
/// search, new session, and PC history import.
struct SidebarView: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var isShowingHistorySheet = false

    @State private var revealedRowId: String?

    // State for renaming session
    @State private var sessionToRename: SessionInfo?
    @State private var renameTitle = ""
    @State private var isShowingRenameAlert = false

    // State for deleting session
    @State private var sessionToDelete: SessionInfo?
    @State private var isShowingDeleteConfirm = false

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. Header with search toggle
                    headerSection

                    // Search field (toggled via header search button or Cmd+K)
                    if isSearching {
                        searchBar
                    }

                    // 2. Top rows: Agents & From your PC (hidden during active search)
                    if !isSearching && searchText.isEmpty {
                        agentRowsSection

                        Rectangle()
                            .fill(Theme.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, 4)
                    }

                    // 3. Pinned & Recents sections
                    SidebarSessionsView(
                        searchText: searchText,
                        revealedRowId: $revealedRowId,
                        onSelectSession: { session in
                            selectSession(session)
                        },
                        onRenameSession: { session in
                            startRenameSession(session)
                        },
                        onDeleteSession: { session in
                            startDeleteSession(session)
                        }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, max(topInset, 16))
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarFooterView {
                    resetSearch()
                    ui.newChat()
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $isShowingHistorySheet) {
            HistoryImportSheet()
        }
        .onChange(of: ui.isSidebarOpen) { _, isOpen in
            if !isOpen {
                revealedRowId = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .linkupFocusSearch)) { _ in
            withAnimation(.snappy(duration: 0.25)) {
                isSearching = true
            }
            isSearchFocused = true
        }
        .accessibilityAction(.escape) {
            ui.openSession(ui.currentSessionId)
        }
        .alert("Rename Session", isPresented: $isShowingRenameAlert) {
            TextField("Session title", text: $renameTitle)
            Button("Save") {
                if let session = sessionToRename {
                    let trimmed = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        withAnimation(.snappy) {
                            store.update(session.id, title: trimmed)
                        }
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
                    withAnimation(.snappy) {
                        store.delete(session.id)
                    }
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
                        isSearchFocused = false
                    } else {
                        isSearchFocused = true
                    }
                }
            } label: {
                Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(isSearching ? "Close search" : "Search chats")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)

            TextField("Search chats", text: $searchText)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 44, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, searchText.isEmpty ? 12 : 2)
        .frame(height: 40)
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

                Button {
                    let isAvailable = store.agent(agentId)?.available == true
                    if !isAvailable {
                        ui.toast = "\(kind.title) is not available"
                    } else {
                        let savedModel = UserDefaults.standard.string(forKey: "draftModel_\(agentId)")
                        ui.draftAgent = agentId
                        ui.draftModel = savedModel
                        resetSearch()
                        ui.newChat()
                    }
                } label: {
                    HStack(spacing: 12) {
                        AgentLogo(agent: agentId, size: 26)
                            .frame(width: 28, height: 28, alignment: .center)

                        Text(kind.title)
                            .font(Theme.sans(19))
                            .foregroundStyle(Theme.text)

                        Spacer()

                        SidebarAgentStatusDot(agentId: agentId)
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

            SidebarToolRow(symbol: "folder", title: "Projects") { ui.isShowingProjects = true }
            SidebarToolRow(symbol: "bolt.horizontal", title: "Running now", badge: { SidebarRunningBadge() }) { ui.isShowingRunning = true }
            SidebarToolRow(symbol: "square.split.2x1", title: "Compare agents") { ui.isShowingCompare = true }
            SidebarToolRow(symbol: "clock", title: "Scheduled") { ui.isShowingSchedules = true }
        }
    }

    // MARK: - Navigation & Actions

    private func selectSession(_ session: SessionInfo) {
        if ui.currentSessionId == session.id {
            store.open(session.id)
        }
        resetSearch()
        ui.openSession(session.id)
    }

    private func resetSearch() {
        if isSearching || !searchText.isEmpty {
            isSearching = false
            searchText = ""
            isSearchFocused = false
        }
    }

    private func startRenameSession(_ session: SessionInfo) {
        sessionToRename = session
        renameTitle = session.title ?? ""
        isShowingRenameAlert = true
    }

    private func startDeleteSession(_ session: SessionInfo) {
        sessionToDelete = session
        isShowingDeleteConfirm = true
    }
}

// MARK: - SidebarAgentStatusDot

private struct SidebarAgentStatusDot: View {
    @Environment(SessionStore.self) private var store
    let agentId: String

    var body: some View {
        let isAvailable = store.agent(agentId)?.available == true
        Circle()
            .fill(isAvailable ? Theme.success : Color(white: 0.45))
            .frame(width: 7, height: 7)
    }
}

// MARK: - SidebarRunningBadge

private struct SidebarRunningBadge: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        let count = store.sessions.filter(\.isRunning).count
        if count > 0 {
            HStack(spacing: 6) {
                WorkingDots()
                Text("\(count)")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
            }
        }
    }
}

// MARK: - SidebarSessionsView

private struct SidebarSessionsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    let searchText: String
    @Binding var revealedRowId: String?
    let onSelectSession: (SessionInfo) -> Void
    let onRenameSession: (SessionInfo) -> Void
    let onDeleteSession: (SessionInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Pinned section
            if !pinnedSessions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pinned")
                        .font(Theme.sans(15, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)

                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(pinnedSessions) { session in
                            SidebarSessionRow(
                                id: session.id,
                                title: session.displayTitle,
                                agent: session.agent,
                                isPinned: session.pinned,
                                isRunning: session.isRunning,
                                hasUnread: session.hasUnread,
                                updatedDate: session.updatedDate,
                                isSelected: ui.currentSessionId == session.id,
                                revealedRowId: $revealedRowId,
                                onSelect: { onSelectSession(session) },
                                onTogglePin: {
                                    withAnimation(.snappy) {
                                        store.update(session.id, pinned: !session.pinned)
                                    }
                                },
                                onRename: { onRenameSession(session) },
                                onDelete: { onDeleteSession(session) }
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
                        .accessibilityAddTraits(.isHeader)

                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(sessions) { session in
                            SidebarSessionRow(
                                id: session.id,
                                title: session.displayTitle,
                                agent: session.agent,
                                isPinned: session.pinned,
                                isRunning: session.isRunning,
                                hasUnread: session.hasUnread,
                                updatedDate: session.updatedDate,
                                isSelected: ui.currentSessionId == session.id,
                                revealedRowId: $revealedRowId,
                                onSelect: { onSelectSession(session) },
                                onTogglePin: {
                                    withAnimation(.snappy) {
                                        store.update(session.id, pinned: !session.pinned)
                                    }
                                },
                                onRename: { onRenameSession(session) },
                                onDelete: { onDeleteSession(session) }
                            )
                        }
                    }
                }
            }

            // No matching results when searching
            if !searchText.isEmpty && filteredSessions.isEmpty {
                Text("No matching chats")
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            }
        }
    }

    private var filteredSessions: [SessionInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).searchFolded
        if query.isEmpty {
            return store.sessions
        }
        return store.sessions.filter { s in
            s.displayTitle.searchFolded.contains(query) ||
            (s.preview?.searchFolded.contains(query) ?? false)
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
}

// MARK: - SidebarSessionRow

private struct SidebarSessionRow: View {
    let id: String
    let title: String
    let agent: String
    let isPinned: Bool
    let isRunning: Bool
    let hasUnread: Bool
    let updatedDate: Date
    let isSelected: Bool
    @Binding var revealedRowId: String?
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var isRevealed: Bool {
        revealedRowId == id
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Trailing action buttons: Pin and Delete
            // Only added to tree when revealed or actively dragging open
            if isRevealed || dragOffset < -10 {
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            dragOffset = 0
                            revealedRowId = nil
                        }
                        onTogglePin()
                    } label: {
                        Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .frame(width: 44, height: 38)
                            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPinned ? "Unpin session" : "Pin session")

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            dragOffset = 0
                            revealedRowId = nil
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
                .accessibilityHidden(!isRevealed)
            }

            // Main row button
            Button {
                if isRevealed {
                    withAnimation(.snappy(duration: 0.2)) {
                        dragOffset = 0
                        revealedRowId = nil
                    }
                } else {
                    onSelect()
                }
            } label: {
                HStack(spacing: 12) {
                    AgentLogo(agent: agent, size: 20)
                        .frame(width: 22, height: 22)

                    Text(title)
                        .font(Theme.sans(18))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .environment(\.layoutDirection, title.dominantLayoutDirection)
                        .multilineTextAlignment(title.isRightToLeft ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: title.isRightToLeft ? .trailing : .leading)

                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.secondaryText)
                    } else if hasUnread {
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
            .highPriorityGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > 2 * abs(dy) else { return }
                        let base: CGFloat = isRevealed ? -100 : 0
                        let total = base + dx
                        dragOffset = min(0, max(-110, total))
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        withAnimation(.snappy(duration: 0.25)) {
                            if abs(dx) > 2 * abs(dy) && (dx < -40 || (isRevealed && dx < 20)) {
                                dragOffset = -100
                                revealedRowId = id
                            } else {
                                dragOffset = 0
                                if revealedRowId == id {
                                    revealedRowId = nil
                                }
                            }
                        }
                    }
            )
        }
        .onChange(of: revealedRowId) { _, currentRevealed in
            if currentRevealed != id && dragOffset != 0 {
                withAnimation(.snappy(duration: 0.2)) {
                    dragOffset = 0
                }
            }
        }
        .contextMenu {
            Button {
                withAnimation(.snappy) { onTogglePin() }
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: isPinned ? "Unpin session" : "Pin session") {
            withAnimation(.snappy) { onTogglePin() }
        }
        .accessibilityAction(named: "Rename session") {
            onRename()
        }
        .accessibilityAction(named: "Delete session") {
            onDelete()
        }
    }

    private var rowAccessibilityLabel: String {
        let agentName = AgentKind(rawValue: agent)?.title ?? agent.capitalized
        var parts: [String] = [title, "\(agentName) agent"]
        if isRunning {
            parts.append("currently running")
        }
        if hasUnread {
            parts.append("unread messages")
        }
        if isPinned {
            parts.append("pinned")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        parts.append(formatter.localizedString(for: updatedDate, relativeTo: Date()))
        return parts.joined(separator: ", ")
    }
}

// MARK: - SidebarFooterView

private struct SidebarFooterView: View {
    @Environment(LinkupClient.self) private var client
    @Environment(UIState.self) private var ui

    let onNewChat: () -> Void

    @State private var isReconnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Connection footer line
            connectionFooter

            // Bottom bar: avatar (44x44) and New session pill (height 44)
            HStack(spacing: 12) {
                Button {
                    ui.isShowingSettings = true
                } label: {
                    Text(avatarLetter)
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Settings")

                Button {
                    onNewChat()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                        Text("New session")
                            .font(Theme.sans(16, weight: .medium))
                    }
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.elevated, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New session")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Theme.background)
    }

    private var connectionFooter: some View {
        Button {
            guard client.state != .connected && client.state != .connecting && !isReconnecting else { return }
            isReconnecting = true
            client.connect()
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                isReconnecting = false
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
        .accessibilityLabel(connectionStatusText)
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
            // Standard SheetHeader with trailing 44pt glass close button
            SheetHeader(title: "Continue from your PC", onClose: {
                dismiss()
            })

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
                            .frame(width: 44, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, searchText.isEmpty ? 12 : 2)
            .frame(height: 40)
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
        .presentationDetents([.large])
        .task {
            await fetchHistory()
        }
    }

    private var filteredItems: [HistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).searchFolded
        if query.isEmpty { return items }
        return items.filter { item in
            item.title.searchFolded.contains(query) ||
            (item.cwd?.searchFolded.contains(query) ?? false)
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
                dismiss()
                ui.openSession(s.id)
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
                // Title (2 lines) with layout direction support
                Text(item.title.isEmpty ? "Untitled Session" : item.title)
                    .font(Theme.sans(16, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, item.title.dominantLayoutDirection)

                // Metadata: project folder name from cwd, relative date, message count
                HStack(spacing: 6) {
                    if let folder = projectFolder {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                        Text(folder)
                            .lineLimit(1)
                        Text("·")
                            .accessibilityHidden(true)
                    }

                    Text(relativeDate)

                    if let count = item.messages {
                        Text("·")
                            .accessibilityHidden(true)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleDescription)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibleDescription: String {
        var parts: [String] = [item.title.isEmpty ? "Untitled Session" : item.title]
        if let folder = projectFolder {
            parts.append("project \(folder)")
        }
        parts.append(relativeDate)
        if let count = item.messages {
            parts.append("\(count) \(count == 1 ? "message" : "messages")")
        }
        return parts.joined(separator: ", ")
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

// MARK: - SidebarToolRow

private struct SidebarToolRow<Badge: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var badge: () -> Badge
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.text)
                    .frame(width: 28, height: 28, alignment: .center)
                Text(title)
                    .font(Theme.sans(19))
                    .foregroundStyle(Theme.text)
                Spacer()
                badge()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension SidebarToolRow where Badge == EmptyView {
    init(symbol: String, title: String, action: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, badge: { EmptyView() }, action: action)
    }
}
