import SwiftUI

/// Project Detail workspace view:
/// - Segmented control: Files | Changes | History | Builds
/// - Toolbar menu "New session here" (sets `ui.draftProject = project.path; ui.newChat()` and dismisses)
/// - Files: `FileBrowserView(path:)`
/// - Changes: `GitStatusView(path:)`
/// - History: `GitHistoryView(path:)`
/// - Builds: `CIRunsView(path:)`
struct ProjectDetailView: View {
    let project: ProjectInfo

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: ProjectTab = .files

    enum ProjectTab: String, CaseIterable, Identifiable {
        case files = "Files"
        case changes = "Changes"
        case history = "History"
        case builds = "Builds"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker bar
            pickerBar

            // Tab content
            tabContentView
        }
        .background(Theme.surface.ignoresSafeArea())
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        startSessionHere()
                    } label: {
                        Label("New session here", systemImage: "plus.bubble")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Project actions")
            }
        }
    }

    private func startSessionHere() {
        Task {
            UserDefaults.standard.set("agent", forKey: "draftMode")
            let permMode = (ui.draftAgent == "claude") ? UserDefaults.standard.string(forKey: "draftPermissionMode") : nil
            do {
                let session = try await store.create(
                    agent: ui.draftAgent,
                    model: ui.draftModel,
                    effort: ui.draftEffort,
                    cwd: project.path,
                    permissionMode: permMode
                )
                ui.draftProject = nil
                ui.openSession(session.id)
                ui.isShowingProjects = false
                dismiss()
            } catch {
                ui.toast = "Couldn\u{2019}t start session: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Picker Bar

    private var pickerBar: some View {
        Picker("View", selection: $selectedTab) {
            ForEach(ProjectTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Theme.background)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.hairline), alignment: .bottom)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContentView: some View {
        switch selectedTab {
        case .files:
            FileBrowserView(path: project.path, title: project.name)
        case .changes:
            GitStatusView(path: project.path)
        case .history:
            GitHistoryView(path: project.path)
        case .builds:
            CIRunsView(path: project.path)
        }
    }
}
