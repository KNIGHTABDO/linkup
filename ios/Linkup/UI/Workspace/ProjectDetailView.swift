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
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        ui.draftProject = project.path
                        ui.newChat()
                        dismiss()
                    } label: {
                        Label("New session here", systemImage: "plus.bubble")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Project actions")
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
