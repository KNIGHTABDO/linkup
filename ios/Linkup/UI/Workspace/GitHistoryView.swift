import SwiftUI
import UIKit

/// Git commit history list:
/// - Commits list (short hash mono, subject, author, relative date)
/// - Tap to view commit diff or copy hash
/// - Pull to refresh
struct GitHistoryView: View {
    let path: String

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var commits: [GitCommit] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedCommit: GitCommit?

    private var filteredCommits: [GitCommit] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return commits }
        return commits.filter {
            $0.subject.localizedCaseInsensitiveContains(q) ||
            $0.short.localizedCaseInsensitiveContains(q) ||
            ($0.author?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        ZStack {
            Theme.surface
                .ignoresSafeArea()

            if isLoading && commits.isEmpty {
                ProgressView()
                    .tint(Theme.accent)
                    .scaleEffect(1.2)
            } else if let error = errorMessage, commits.isEmpty {
                errorView(error)
            } else if commits.isEmpty {
                emptyHistoryView
            } else {
                listView
            }
        }
        .task {
            await loadCommits()
        }
        .refreshable {
            await loadCommits()
        }
        .sheet(item: $selectedCommit) { commit in
            GitCommitDetailSheet(path: path, commit: commit)
        }
    }

    // MARK: - List View

    private var listView: some View {
        List {
            Section {
                ForEach(filteredCommits) { commit in
                    Button {
                        selectedCommit = commit
                    } label: {
                        commitRow(commit)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.elevated)
                    .listRowSeparatorTint(Theme.hairline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .searchable(text: $searchText, prompt: "Search commits…")
    }

    // MARK: - Row

    private func commitRow(_ commit: GitCommit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(commit.short)
                    .font(Theme.mono(12))
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Spacer()

                if let date = commit.date {
                    Text(WorkspaceFormatters.relative(timestamp: date))
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            Text(commit.subject)
                .font(Theme.sans(17, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)

            if let author = commit.author, !author.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)

                    Text(author)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty & Error Views

    private var emptyHistoryView: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(Theme.tertiaryText)

            Text("No commit history")
                .font(Theme.sans(18, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("No git commits found in this workspace.")
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
                Task { await loadCommits() }
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

    private func loadCommits() async {
        if commits.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        do {
            let loaded = try await store.gitLog(path)
            commits = loaded
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Commit Detail Sheet

private struct GitCommitDetailSheet: View {
    let path: String
    let commit: GitCommit

    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedPill = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(commit.subject)
                                .font(Theme.sans(20, weight: .semibold))
                                .foregroundStyle(Theme.text)

                            HStack(spacing: 8) {
                                Text(commit.short)
                                    .font(Theme.mono(13))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Theme.accent.opacity(0.12), in: Capsule())

                                Button {
                                    UIPasteboard.general.string = commit.hash
                                    ui.toast = "Full hash copied"
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    withAnimation(.snappy(duration: 0.2)) {
                                        showCopiedPill = true
                                    }
                                    Task {
                                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                                        withAnimation(.snappy(duration: 0.2)) {
                                            showCopiedPill = false
                                        }
                                    }
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.secondaryText)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Copy full hash")

                                Spacer()

                                if let date = commit.date {
                                    Text(WorkspaceFormatters.relative(timestamp: date))
                                        .font(Theme.sans(13))
                                        .foregroundStyle(Theme.tertiaryText)
                                }
                            }
                        }
                        .padding(16)
                        .background(Theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))

                        if let author = commit.author, !author.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Theme.accent)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Author")
                                        .font(Theme.sans(11))
                                        .foregroundStyle(Theme.tertiaryText)
                                    Text(author)
                                        .font(Theme.sans(15, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                }

                                Spacer()
                            }
                            .padding(14)
                            .background(Theme.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
                        }

                        // Full hash box
                        VStack(alignment: .leading, spacing: 4) {
                            Text("COMMIT HASH")
                                .font(Theme.sans(11, weight: .semibold))
                                .foregroundStyle(Theme.tertiaryText)

                            Text(commit.hash)
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.secondaryText)
                                .textSelection(.enabled)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
                    }
                    .padding(16)
                }

                if showCopiedPill {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.success)
                            Text("Full hash copied")
                                .font(Theme.sans(14, weight: .medium))
                                .foregroundStyle(Theme.text)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.elevated)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .navigationTitle("Commit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton(action: { dismiss() })
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
    }
}
