import SwiftUI

/// Drill-down file browser:
/// - Folders first, sorted alphabetically
/// - Files sorted alphabetically with size and modified timestamp
/// - File icons by extension
/// - Pull to refresh
/// - Tap file → `FileViewer(path:)`
/// - Tap folder → drills down into `FileBrowserView(path:)`
struct FileBrowserView: View {
    let path: String
    var title: String? = nil

    init(path: String, title: String? = nil) {
        self.path = path
        self.title = title
    }

    @Environment(SessionStore.self) private var store

    @State private var entries: [FileEntry] = []
    @State private var isLoading = true
    @State private var inFlightLoad = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var folderTitle: String {
        if let title, !title.isEmpty { return title }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "Files" : name
    }

    private var sortedEntries: [FileEntry] {
        let filtered = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? entries
            : entries.filter { $0.name.searchFolded.contains(searchText.searchFolded) }

        let dirs = filtered.filter(\.isDir).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let files = filtered.filter { !$0.isDir }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return dirs + files
    }

    var body: some View {
        ZStack {
            Theme.surface
                .ignoresSafeArea()

            if isLoading && entries.isEmpty {
                ProgressView()
                    .tint(Theme.accent)
                    .scaleEffect(1.2)
            } else if let error = errorMessage, entries.isEmpty {
                errorView(error)
            } else if entries.isEmpty {
                emptyFolderView
            } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sortedEntries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                listView
            }
        }
        .navigationTitle(folderTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search files…")
        .navigationDestination(for: FileEntry.self) { entry in
            if entry.isDir {
                FileBrowserView(path: entry.path)
            } else {
                FileViewer(path: entry.path)
            }
        }
        .task {
            await loadFiles()
        }
        .refreshable {
            await loadFiles()
        }
    }

    // MARK: - List View

    private var listView: some View {
        VStack(spacing: 0) {
            if let error = errorMessage, !entries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                    Text(error)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    Button("Dismiss") {
                        errorMessage = nil
                    }
                    .font(Theme.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
                .padding(10)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            List {
                if !entries.isEmpty {
                    Section {
                        ForEach(sortedEntries) { entry in
                            NavigationLink(value: entry) {
                                fileRow(entry)
                            }
                            .listRowBackground(Theme.surface)
                            .listRowSeparatorTint(Theme.hairline)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
        }
    }

    // MARK: - Row

    private func fileRow(_ entry: FileEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: WorkspaceFormatters.fileIcon(for: entry.name, isDir: entry.isDir))
                .font(.system(size: 18))
                .foregroundStyle(entry.isDir ? Theme.accent : Theme.secondaryText)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(Theme.sans(17))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let subtitle = rowSubtitle(for: entry) {
                    Text(subtitle)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func rowSubtitle(for entry: FileEntry) -> String? {
        var parts: [String] = []
        if let size = entry.size, !entry.isDir {
            parts.append(WorkspaceFormatters.fileSize(size))
        }
        if let modified = entry.modified {
            let rel = WorkspaceFormatters.relative(timestamp: modified)
            if !rel.isEmpty {
                parts.append(rel)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Empty & Error Views

    private var emptyFolderView: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 44))
                .foregroundStyle(Theme.tertiaryText)

            Text("This folder is empty")
                .font(Theme.sans(18, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("No files or subdirectories found.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.danger)

            Text(error)
                .font(Theme.sans(15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task { await loadFiles() }
            } label: {
                Text("Retry")
                    .font(Theme.sans(15, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadFiles() async {
        guard !inFlightLoad else { return }
        inFlightLoad = true
        defer { inFlightLoad = false }

        if entries.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        do {
            let loaded = try await store.listFiles(path)
            entries = loaded
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}
