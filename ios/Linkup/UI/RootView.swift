import SwiftUI
import UIKit

/// The sheets the shell can present. One router keeps exactly one sheet up at a time (the newest request wins).
private enum ActiveSheet: Hashable, Identifiable {
    case settings, connect, usage, projects, running, compare, schedules, modelPicker, summary
    case handoff(String)

    var id: Self { self }
}

private enum ActiveCover: Hashable, Identifiable {
    case artifact
    case preview(Int)

    var id: Self { self }
}

/// Every flag that can ask for a sheet, compared as one value so the newest request can be told apart.
private struct SheetFlags: Equatable {
    var settings = false
    var connect = false
    var usage = false
    var projects = false
    var running = false
    var compare = false
    var schedules = false
    var modelPicker = false
    var summary = false
    var handoff: String?

    var requested: [ActiveSheet] {
        var result: [ActiveSheet] = []
        if settings { result.append(.settings) }
        if connect { result.append(.connect) }
        if usage { result.append(.usage) }
        if projects { result.append(.projects) }
        if running { result.append(.running) }
        if compare { result.append(.compare) }
        if schedules { result.append(.schedules) }
        if modelPicker { result.append(.modelPicker) }
        if summary { result.append(.summary) }
        if let handoff { result.append(.handoff(handoff)) }
        return result
    }
}

/// Root shell: one stable tree (sidebar layer, chat layer, inspector layer) that adapts between the iPhone drawer
/// and the iPad split layout without ever rebuilding the chat.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(ConnectionSettings.self) private var settings
    @Environment(LinkupClient.self) private var client
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var width: CGFloat = RootView.initialWidth()
    @State private var dragX: CGFloat?
    @GestureState private var dragActive = false
    @State private var isIPadSidebarVisible = true
    @State private var presented: ActiveSheet?
    @State private var cover: ActiveCover?

    private static func initialWidth() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 390
    }

    // MARK: Geometry

    /// Wide split layout only on a roomy iPad window; Slide Over, narrow Split View and phones use the drawer.
    private var isWide: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && width >= 700
    }

    private var drawerWidth: CGFloat { min(340, width * 0.82) }
    private var padSidebarWidth: CGFloat { width >= 1000 ? 320 : 300 }
    private var inspectorWidth: CGFloat { min(380, width * 0.9) }
    private var isInspectorOpen: Bool { ui.summaryTurn != nil || ui.openArtifact != nil }

    private var wideSidebarShown: Bool {
        isWide && isIPadSidebarVisible
            && (!isInspectorOpen || width - padSidebarWidth - inspectorWidth >= 500)
    }

    private var wideInspectorInline: Bool {
        isWide && isInspectorOpen
            && width - (wideSidebarShown ? padSidebarWidth : 0) - inspectorWidth >= 500
    }

    private var drawerOffset: CGFloat {
        let base: CGFloat = ui.isSidebarOpen ? drawerWidth : 0
        return min(max(base + (dragX ?? 0), 0), drawerWidth)
    }

    private var progress: CGFloat {
        guard !isWide, drawerWidth > 0 else { return 0 }
        return drawerOffset / drawerWidth
    }

    private var mainOffset: CGFloat {
        isWide ? (wideSidebarShown ? padSidebarWidth : 0) : drawerOffset
    }

    private var mainWidth: CGFloat {
        if isWide {
            return max(width - mainOffset - (wideInspectorInline ? inspectorWidth : 0), 320)
        }
        return width
    }

    private var drawerSpring: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    private var flags: SheetFlags {
        SheetFlags(
            settings: ui.isShowingSettings,
            connect: ui.isShowingConnect,
            usage: ui.isShowingUsage,
            projects: ui.isShowingProjects,
            running: ui.isShowingRunning,
            compare: ui.isShowingCompare,
            schedules: ui.isShowingSchedules,
            modelPicker: ui.isShowingModelPicker,
            summary: !isWide && ui.summaryTurn != nil,
            handoff: ui.handoffSessionId
        )
    }

    private var coverRequest: ActiveCover? {
        if let port = ui.previewPort { return .preview(port) }
        if !isWide, ui.openArtifact != nil { return .artifact }
        return nil
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.background.ignoresSafeArea()

            sidebarLayer
            mainLayer

            if isWide && isInspectorOpen {
                inspectorLayer
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            ToastHost()
        }
        .animation(.smooth(duration: 0.35), value: wideSidebarShown)
        .animation(.smooth(duration: 0.35), value: wideInspectorInline)
        .animation(.smooth(duration: 0.35), value: isInspectorOpen)
        .animation(drawerSpring, value: ui.isSidebarOpen)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if newWidth > 0, abs(newWidth - width) > 0.5 { width = newWidth }
        }
        .background { SessionGuard() }
        .background { keyboardShortcuts }
        .usageAlerts()
        .sheet(item: $presented) { sheet in
            sheetContent(sheet)
                .presentationDetents(detents(for: sheet))
                .presentationBackground(Theme.surface)
                .interactiveDismissDisabled(sheet == .connect && !settings.isConfigured)
        }
        .fullScreenCover(item: $cover) { item in
            coverContent(item)
        }
        .alert(
            "Replace saved PC?",
            isPresented: Binding(
                get: { ui.pendingPairingURL != nil },
                set: { if !$0 { ui.pendingPairingURL = nil } }
            ),
            presenting: ui.pendingPairingURL
        ) { url in
            Button("Replace", role: .destructive) { app.pair(with: url) }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("Linkup is already paired. Switch to \(pairingHost(url))?")
        }
        .onChange(of: flags) { old, new in syncSheets(old: old.requested, new: new.requested) }
        .onChange(of: presented) { old, new in
            if let old, old != new { clearFlag(for: old) }
        }
        .onChange(of: coverRequest) { _, new in cover = new }
        .onChange(of: cover) { old, new in
            if new == nil, let old { clearFlag(for: old) }
        }
        .onChange(of: ui.isSidebarOpen) { _, isOpen in
            if isOpen { resignKeyboard() }
        }
        .onChange(of: store.lastError) { _, error in
            if let error, !error.isEmpty {
                ui.toast = error
                store.clearError()
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
            if let initial = flags.requested.last { presented = initial }
            cover = coverRequest
        }
    }

    // MARK: Layers

    private var sidebarLayer: some View {
        let visible = isWide ? wideSidebarShown : progress > 0.001
        let sidebarWidth = isWide ? padSidebarWidth : drawerWidth
        return SidebarView()
            .frame(width: sidebarWidth)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                if isWide {
                    Rectangle().fill(Theme.hairline).frame(width: 1).ignoresSafeArea()
                }
            }
            .opacity(isWide ? (wideSidebarShown ? 1 : 0) : progress)
            .offset(x: isWide ? (wideSidebarShown ? 0 : -sidebarWidth) : -40 * (1 - progress))
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }

    private var mainLayer: some View {
        let open = !isWide && (ui.isSidebarOpen || progress > 0.001)
        return ChatView(
            sessionId: ui.currentSessionId,
            sidebarLabel: isWide ? (wideSidebarShown ? "Hide sidebar" : "Show sidebar") : "Open sidebar",
            onSidebar: toggleSidebar
        )
        .allowsHitTesting(!open)
        .accessibilityHidden(open)
        .frame(width: mainWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .overlay {
            if open {
                Color.black.opacity(0.35 * progress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { setSidebar(open: false) }
                    .accessibilityElement()
                    .accessibilityLabel("Close sidebar")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { setSidebar(open: false) }
            }
        }
        .mask {
            RoundedRectangle(cornerRadius: 22 * min(progress * 4, 1), style: .continuous)
                .ignoresSafeArea()
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.4 * progress), radius: 18, x: -4, y: 0)
        .overlay(alignment: .trailing) {
            if wideInspectorInline {
                Rectangle().fill(Theme.hairline).frame(width: 1).ignoresSafeArea()
            }
        }
        .offset(x: mainOffset)
        .simultaneousGesture(drawerDrag, including: isWide ? .none : .all)
        .onChange(of: dragActive) { _, active in
            // A cancelled gesture (system interruption) never calls onEnded: snap back to the resting state.
            if !active, dragX != nil { withAnimation(drawerSpring) { dragX = nil } }
        }
    }

    private var inspectorLayer: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            InspectorView(width: inspectorWidth)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.hairline).frame(width: 1).ignoresSafeArea()
                }
                .shadow(color: .black.opacity(wideInspectorInline ? 0 : 0.35), radius: 16, x: -4, y: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Drawer gesture

    private var drawerDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($dragActive) { _, state, _ in state = true }
            .onChanged { value in
                if dragX == nil {
                    let horizontal = abs(value.translation.width) > abs(value.translation.height)
                    guard horizontal else { return }
                    if !ui.isSidebarOpen {
                        // Narrow edge zone, only for rightward drags that begin at the screen edge.
                        guard value.startLocation.x < 20, value.translation.width > 0 else { return }
                    }
                }
                dragX = value.translation.width
            }
            .onEnded { value in
                guard dragX != nil else { return }
                let final = (ui.isSidebarOpen ? drawerWidth : 0) + value.translation.width
                let velocity = value.velocity.width
                let shouldOpen: Bool
                if abs(velocity) > 500 {
                    shouldOpen = velocity > 0
                } else {
                    shouldOpen = final > drawerWidth * 0.5
                }
                withAnimation(drawerSpring) {
                    ui.isSidebarOpen = shouldOpen
                    dragX = nil
                }
            }
    }

    private func setSidebar(open: Bool) {
        withAnimation(drawerSpring) {
            ui.isSidebarOpen = open
            dragX = nil
        }
    }

    private func toggleSidebar() {
        if isWide {
            withAnimation(.smooth(duration: 0.35)) { isIPadSidebarVisible.toggle() }
        } else {
            setSidebar(open: true)
        }
    }

    private func resignKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: Sheet routing

    private func syncSheets(old: [ActiveSheet], new: [ActiveSheet]) {
        if let added = new.last(where: { !old.contains($0) }) {
            for other in new where other != added { clearFlag(for: other) }
            if ui.isSidebarOpen && !isWide { setSidebar(open: false) }
            presented = added
        } else if let current = presented, !new.contains(current) {
            presented = nil
        }
    }

    private func clearFlag(for sheet: ActiveSheet) {
        switch sheet {
        case .settings: ui.isShowingSettings = false
        case .connect: ui.isShowingConnect = false
        case .usage: ui.isShowingUsage = false
        case .projects: ui.isShowingProjects = false
        case .running: ui.isShowingRunning = false
        case .compare: ui.isShowingCompare = false
        case .schedules: ui.isShowingSchedules = false
        case .modelPicker: ui.isShowingModelPicker = false
        case .summary: ui.summaryTurn = nil
        case .handoff: ui.handoffSessionId = nil
        }
    }

    private func clearFlag(for cover: ActiveCover) {
        switch cover {
        case .artifact: ui.openArtifact = nil
        case .preview: ui.previewPort = nil
        }
    }

    private func detents(for sheet: ActiveSheet) -> Set<PresentationDetent> {
        sheet == .modelPicker ? [.medium, .large] : [.large]
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .settings: SettingsView()
        case .connect: ConnectView()
        case .usage: UsageView()
        case .projects: ProjectsView()
        case .running: NavigationStack { RunningNowView() }
        case .compare: CompareSheet()
        case .schedules: SchedulesView()
        case .modelPicker: ModelPickerSheet(sessionId: ui.currentSessionId)
        case .summary:
            if let turn = ui.summaryTurn { SummarySheet(turn: turn) }
        case .handoff(let id): HandoffSheet(sessionId: id)
        }
    }

    @ViewBuilder
    private func coverContent(_ item: ActiveCover) -> some View {
        switch item {
        case .artifact:
            if let artifact = ui.openArtifact { ArtifactViewer(artifact: artifact) }
        case .preview(let port):
            NavigationStack { DevServerPreview(port: port) }
        }
    }

    private func pairingHost(_ url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let raw = components?.queryItems?.first(where: { $0.name == "url" })?.value
        return raw.flatMap { URL(string: $0)?.host } ?? raw ?? "a new PC"
    }

    // MARK: Shortcuts

    private var keyboardShortcuts: some View {
        Group {
            Button("New Chat") { ui.newChat() }
                .keyboardShortcut("n", modifiers: .command)

            Button("Focus Search") {
                if isWide {
                    if !isIPadSidebarVisible {
                        withAnimation(.smooth(duration: 0.35)) { isIPadSidebarVisible = true }
                    }
                } else if !ui.isSidebarOpen {
                    setSidebar(open: true)
                }
                NotificationCenter.default.post(name: .linkupFocusSearch, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Stop") {
                if let current = ui.currentSessionId { store.interrupt(current) }
            }
            .keyboardShortcut(".", modifiers: .command)

            Button("Toggle Sidebar") {
                if isWide {
                    withAnimation(.smooth(duration: 0.35)) { isIPadSidebarVisible.toggle() }
                } else {
                    setSidebar(open: !ui.isSidebarOpen)
                }
            }
            .keyboardShortcut("[", modifiers: .command)

            Button("Settings") { ui.isShowingSettings = true }
                .keyboardShortcut(",", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Helpers

/// Leaves a chat that was deleted while open (from any screen, or by the bridge) for the new-chat screen.
private struct SessionGuard: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        let ids = store.sessions.map(\.id)
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: ids) { old, new in
                if let current = ui.currentSessionId, old.contains(current), !new.contains(current) {
                    ui.newChat()
                }
            }
    }
}

/// Transient message; its own view so a toast never re-renders the shell. The timer restarts per toast.
private struct ToastHost: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        ZStack {
            if let text = ui.toast {
                Text(text)
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.elevated, in: Capsule())
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(.smooth) { ui.toast = nil } }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth, value: ui.toast)
        .onChange(of: ui.toast) { _, text in
            if let text { AccessibilityNotification.Announcement(text).post() }
        }
        .task(id: ui.toastID) {
            guard let text = ui.toast else { return }
            try? await Task.sleep(for: .seconds(max(3, Double(text.count) * 0.06)))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { ui.toast = nil }
        }
    }
}
