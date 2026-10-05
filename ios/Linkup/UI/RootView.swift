import SwiftUI
import UIKit

/// Root shell view: drawer sidebar, main chat layer, top bar overlay, and sheet routing.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(ConnectionSettings.self) private var settings
    @Environment(LinkupClient.self) private var client
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isRenaming = false
    @State private var renameTitle = ""
    @State private var isConfirmingDelete = false

    private struct ShellTurnItem: Identifiable {
        let turn: AssistantTurn
        var id: String { turn.id }
    }

    private var summaryTurnBinding: Binding<ShellTurnItem?> {
        Binding(
            get: { ui.summaryTurn.map(ShellTurnItem.init) },
            set: { ui.summaryTurn = $0?.turn }
        )
    }

    private var currentSession: SessionInfo? {
        guard let id = ui.currentSessionId else { return nil }
        return store.session(id)
    }

    private func sessionSubtitle(for session: SessionInfo) -> String {
        let agentName = store.agent(session.agent)?.name
            ?? AgentKind(rawValue: session.agent)?.title
            ?? session.agent.capitalized
        if let project = session.projectName, !project.isEmpty {
            return "\(agentName) · \(project)"
        }
        return agentName
    }

    private var shouldShowConnectionPill: Bool {
        switch client.state {
        case .connecting, .offline:
            return true
        case .connected, .notConfigured:
            return false
        }
    }

    private var connectionDotColor: Color {
        switch client.state {
        case .connecting:
            return Theme.accent
        case .offline:
            return Theme.danger
        default:
            return Theme.secondaryText
        }
    }

    private func computeOffset(drawerWidth: CGFloat) -> CGFloat {
        let base: CGFloat = ui.isSidebarOpen ? drawerWidth : 0
        let total = base + dragOffset
        if total < 0 {
            return total * 0.2
        } else if total > drawerWidth {
            return drawerWidth + (total - drawerWidth) * 0.2
        } else {
            return total
        }
    }

    var body: some View {
        @Bindable var ui = ui

        GeometryReader { proxy in
            let screenWidth = proxy.size.width
            let drawerWidth = UIDevice.current.userInterfaceIdiom == .pad ? 340 : (screenWidth * 0.82)
            let currentOffset = computeOffset(drawerWidth: drawerWidth)
            let openProgress = max(0, min(1, currentOffset / drawerWidth))

            ZStack(alignment: .leading) {
                Theme.background
                    .ignoresSafeArea()

                // Sidebar layer underneath on the left
                SidebarView()
                    .frame(width: drawerWidth)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(!ui.isSidebarOpen && dragOffset == 0)
                    .allowsHitTesting(ui.isSidebarOpen || dragOffset > 0)

                // Main layer sliding over sidebar
                mainLayer(
                    proxy: proxy,
                    drawerWidth: drawerWidth,
                    currentOffset: currentOffset,
                    openProgress: openProgress
                )
            }
            .overlay(alignment: .top) {
                toastView(safeAreaTop: proxy.safeAreaInsets.top)
            }
        }
        .sheet(isPresented: $ui.isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $ui.isShowingConnect) {
            ConnectView()
                .interactiveDismissDisabled(!settings.isConfigured)
        }
        .sheet(isPresented: $ui.isShowingUsage) {
            UsageView()
        }
        .sheet(isPresented: $ui.isShowingModelPicker) {
            ModelPickerSheet(sessionId: ui.currentSessionId)
        }
        .sheet(item: summaryTurnBinding) { item in
            SummarySheet(turn: item.turn)
        }
        .fullScreenCover(item: $ui.openArtifact) { artifact in
            ArtifactViewer(artifact: artifact)
        }
        .alert("Rename", isPresented: $isRenaming) {
            TextField("Title", text: $renameTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let id = ui.currentSessionId {
                    let trimmed = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.update(id, title: trimmed)
                }
            }
        }
        .confirmationDialog("Delete session?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = ui.currentSessionId {
                    store.delete(id)
                    ui.newChat()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this session? This action cannot be undone.")
        }
        .onChange(of: ui.isSidebarOpen) { _, isOpen in
            if !isOpen {
                dragOffset = 0
            }
        }
        .onChange(of: store.lastError) { _, error in
            if let error, !error.isEmpty {
                ui.toast = error
                store.clearError()
            }
        }
        .task(id: ui.toast) {
            guard ui.toast != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.smooth) {
                ui.toast = nil
            }
        }
        .onAppear {
            if let error = store.lastError, !error.isEmpty {
                ui.toast = error
                store.clearError()
            }
            if client.state == .notConfigured && !settings.isConfigured && DebugLaunch.screen == nil {
                ui.isShowingConnect = true
            }
        }
    }

    @ViewBuilder
    private func mainLayer(
        proxy: GeometryProxy,
        drawerWidth: CGFloat,
        currentOffset: CGFloat,
        openProgress: CGFloat
    ) -> some View {
        ZStack(alignment: .top) {
            ChatView(sessionId: ui.currentSessionId)
                .id(ui.currentSessionId ?? "new")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)

            if openProgress > 0 {
                Color.black.opacity(0.35 * openProgress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.smooth(duration: 0.35)) {
                            ui.isSidebarOpen = false
                            dragOffset = 0
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .local)
                            .onChanged { value in
                                isDragging = true
                                let translation = value.translation.width
                                if translation < 0 {
                                    dragOffset = translation
                                } else {
                                    dragOffset = translation * 0.2
                                }
                            }
                            .onEnded { value in
                                guard isDragging else { return }
                                isDragging = false
                                let predicted = value.predictedEndTranslation.width
                                let shouldClose = value.translation.width < -drawerWidth * 0.35 || predicted < -drawerWidth * 0.4
                                withAnimation(.smooth(duration: 0.35)) {
                                    ui.isSidebarOpen = !shouldClose
                                    dragOffset = 0
                                }
                            }
                    )
            }

            topBarSection(safeAreaTop: proxy.safeAreaInsets.top)
                .allowsHitTesting(openProgress == 0)

            if !ui.isSidebarOpen && openProgress == 0 {
                edgeSwipeZone(drawerWidth: drawerWidth)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        .offset(x: currentOffset)
        .clipShape(RoundedRectangle(cornerRadius: openProgress > 0 ? 20 : 0, style: .continuous))
        .shadow(color: Color.black.opacity(openProgress > 0 ? 0.35 : 0), radius: 16, x: -4, y: 0)
    }

    @ViewBuilder
    private func topBarSection(safeAreaTop: CGFloat) -> some View {
        GlassEffectContainer {
            VStack(spacing: 8) {
                topBarRow
                if shouldShowConnectionPill {
                    connectionPill
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: shouldShowConnectionPill)
            .padding(.horizontal, 16)
            .padding(.top, max(safeAreaTop, 8))
        }
    }

    @ViewBuilder
    private var topBarRow: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.35)) {
                    ui.isSidebarOpen = true
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Open sidebar")

            Spacer()

            HStack(spacing: 0) {
                Button {
                    ui.newChat()
                } label: {
                    Image(systemName: "plus.bubble.fill")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New chat")

                Menu {
                    Button {
                        ui.isShowingUsage = true
                    } label: {
                        Label("Usage", systemImage: "chart.bar")
                    }

                    Button {
                        ui.isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }

                    if let session = currentSession {
                        Divider()

                        Button {
                            renameTitle = session.title ?? session.displayTitle
                            isRenaming = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button {
                            store.update(session.id, pinned: !session.pinned)
                        } label: {
                            Label(session.pinned ? "Unpin" : "Pin", systemImage: session.pinned ? "pin.slash" : "pin")
                        }

                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options")
            }
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .overlay {
            if let session = currentSession {
                Button {
                    ui.isShowingModelPicker = true
                } label: {
                    VStack(spacing: 2) {
                        Text(session.displayTitle)
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(sessionSubtitle(for: session))
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 96)
                .accessibilityLabel("\(session.displayTitle), \(sessionSubtitle(for: session)). Tap to choose model")
            }
        }
    }

    @ViewBuilder
    private var connectionPill: some View {
        Button {
            client.connect()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionDotColor)
                    .frame(width: 7, height: 7)
                Text(client.state.label)
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Connection: \(client.state.label). Tap to connect.")
    }

    @ViewBuilder
    private func edgeSwipeZone(drawerWidth: CGFloat) -> some View {
        HStack {
            Color.clear
                .frame(width: 28)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .onChanged { value in
                            if value.startLocation.x <= 28 && value.translation.width > 0 {
                                isDragging = true
                                dragOffset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            guard isDragging else { return }
                            isDragging = false
                            let predicted = value.predictedEndTranslation.width
                            let shouldOpen = value.translation.width > drawerWidth * 0.35 || predicted > drawerWidth * 0.4
                            withAnimation(.smooth(duration: 0.35)) {
                                ui.isSidebarOpen = shouldOpen
                                dragOffset = 0
                            }
                        }
                )
            Spacer()
        }
    }

    @ViewBuilder
    private func toastView(safeAreaTop: CGFloat) -> some View {
        if let toast = ui.toast {
            HStack(spacing: 8) {
                Text(toast)
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, max(safeAreaTop, 8) + 8)
            .padding(.horizontal, 24)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(100)
            .onTapGesture {
                withAnimation(.smooth) {
                    ui.toast = nil
                }
            }
        }
    }
}
