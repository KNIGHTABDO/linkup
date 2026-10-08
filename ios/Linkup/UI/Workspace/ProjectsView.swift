import SwiftUI

/// Workspace projects list:
/// - List of `store.projects` (folder icon, name, path tail) with search
/// - "+" toolbar button presenting `NewProjectSheet`
/// - Tap → `ProjectDetailView(project:)`
/// - `.task { await store.loadProjects() }`
struct ProjectsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var isShowingNewProject = false
    @State private var newlyCreatedProject: ProjectInfo?

    private var filteredProjects: [ProjectInfo] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.projects }
        return store.projects.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.path.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Theme.surface
                    .ignoresSafeArea()

                if store.projects.isEmpty && searchText.isEmpty {
                    emptyProjectsView
                } else {
                    projectsListView
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ProjectInfo.self) { project in
                ProjectDetailView(project: project)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingNewProject = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("New project")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton(action: { dismiss() })
                }
            }
            .sheet(isPresented: $isShowingNewProject, onDismiss: {
                if let created = newlyCreatedProject {
                    navigationPath.append(created)
                    newlyCreatedProject = nil
                }
            }) {
                NewProjectSheet { created in
                    newlyCreatedProject = created
                }
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
        .task {
            await store.loadProjects()
        }
        .refreshable {
            await store.loadProjects()
        }
    }

    // MARK: - List View

    private var projectsListView: some View {
        List {
            Section {
                ForEach(filteredProjects) { project in
                    NavigationLink(value: project) {
                        projectRow(project)
                    }
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.hairline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $searchText, prompt: "Search projects…")
    }

    // MARK: - Row

    private func projectRow(_ project: ProjectInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(Theme.sans(17))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(WorkspaceFormatters.pathTail(project.path))
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyProjectsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(Theme.tertiaryText)

            Text("No projects yet")
                .font(Theme.sans(20, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("Create a new project on your PC to get started.")
                .font(Theme.sans(15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                isShowingNewProject = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("New project")
                        .font(Theme.sans(16, weight: .semibold))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
            .buttonStyle(.glassProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
