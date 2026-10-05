import SwiftUI
import UIKit

/// Git Changes panel:
/// - Branch + ahead/behind header
/// - Changed files list with colored status badges (M orange, A green, D red, ?? grey)
/// - Tap file → unified diff view (coloured +/- lines, bold headers)
/// - Commit box (TextField message + Commit + Push glass buttons, results/errors as toasts)
/// - "Not a git repository" state
struct GitStatusView: View {
    let path: String

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var status: GitStatus?
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Commit & Push state
    @State private var commitMessage = ""
    @State private var isCommitting = false
    @State private var isPushing = false

    // Selected file for diff sheet
    @State private var selectedFileForDiff: GitFileChange?
    @State private var isShowingFullDiff = false

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            if isLoading && status == nil {
                ProgressView()
                    .tint(Theme.accent)
                    .scaleEffect(1.2)
            } else if let error = errorMessage, status == nil {
                errorView(error)
            } else if let status {
                if !status.isRepo {
                    notAGitRepoView
                } else {
                    mainStatusContent(status)
                }
            }
        }
        .sheet(item: $selectedFileForDiff) { change in
            GitDiffSheet(path: path, file: change.path, status: change.status)
        }
        .sheet(isPresented: $isShowingFullDiff) {
            GitDiffSheet(path: path, file: nil, status: nil)
        }
        .task {
            await loadStatus()
        }
        .refreshable {
            await loadStatus()
        }
    }

    // MARK: - Main Content

    private func mainStatusContent(_ status: GitStatus) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                // 1. Branch + ahead/behind header card
                branchHeaderCard(status)

                // 2. Changed files section
                filesSection(status)

                // 3. Commit box
                commitBox

                Spacer(minLength: 40)
            }
            .padding(16)
        }
    }

    // MARK: - Branch Header

    private func branchHeaderCard(_ status: GitStatus) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                Text(status.branch ?? "HEAD")
                    .font(Theme.sans(17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Spacer()

                if let ahead = status.ahead, ahead > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(ahead)")
                            .font(Theme.sans(12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.success.opacity(0.14), in: Capsule())
                }

                if let behind = status.behind, behind > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(behind)")
                            .font(Theme.sans(12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.danger.opacity(0.14), in: Capsule())
                }
            }

            if let remote = status.remote, !remote.isEmpty {
                HStack(spacing: 6) {
                    Text("Remote:")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.tertiaryText)
                    Text(remote)
                        .font(Theme.sans(12, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Files Section

    private func filesSection(_ status: GitStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status.clean ? "WORKING TREE CLEAN" : "CHANGED FILES (\(status.files.count))")
                    .font(Theme.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)

                Spacer()

                if !status.clean {
                    Button("View full diff") {
                        isShowingFullDiff = true
                    }
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 4)

            if status.clean {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.success)

                    Text("No local changes to commit")
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.secondaryText)

                    Spacer()
                }
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(status.files.enumerated()), id: \.element.id) { index, file in
                        Button {
                            selectedFileForDiff = file
                        } label: {
                            fileRow(file)
                        }
                        .buttonStyle(.plain)

                        if index < status.files.count - 1 {
                            Divider()
                                .overlay(Theme.hairline)
                                .padding(.leading, 46)
                        }
                    }
                }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }

    private func fileRow(_ file: GitFileChange) -> some View {
        let filename = URL(fileURLWithPath: file.path).lastPathComponent
        let dir = (file.path as NSString).deletingLastPathComponent

        return HStack(spacing: 12) {
            statusBadge(file.status)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(Theme.sans(17))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !dir.isEmpty && dir != "." {
                    Text(dir)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func statusBadge(_ code: String) -> some View {
        let cleanCode = code.trimmingCharacters(in: .whitespaces)
        let color: Color
        let label: String

        switch cleanCode {
        case "M":
            color = Color(red: 0.95, green: 0.60, blue: 0.20) // Orange
            label = "M"
        case "A":
            color = Theme.success // Green
            label = "A"
        case "D":
            color = Theme.danger // Red
            label = "D"
        case "??":
            color = Theme.secondaryText // Grey
            label = "??"
        case "R":
            color = Color(red: 0.70, green: 0.50, blue: 0.95) // Purple
            label = "R"
        default:
            color = Theme.secondaryText
            label = cleanCode
        }

        return Text(label)
            .font(Theme.mono(12))
            .fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Commit Box

    private var commitBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMMIT & PUSH")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                TextField("Commit message…", text: $commitMessage, axis: .vertical)
                    .lineLimit(2...4)
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.text)
                    .padding(12)
                    .background(Theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))

                HStack(spacing: 12) {
                    Button {
                        performCommit()
                    } label: {
                        HStack(spacing: 6) {
                            if isCommitting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            Text("Commit")
                                .font(Theme.sans(15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCommitting || isPushing)

                    Button {
                        performPush()
                    } label: {
                        HStack(spacing: 6) {
                            if isPushing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(Theme.text)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            Text("Push")
                                .font(Theme.sans(15, weight: .semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                    }
                    .buttonStyle(.glass)
                    .disabled(isCommitting || isPushing)
                }
            }
            .padding(14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func performCommit() {
        let msg = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !isCommitting else { return }

        isCommitting = true
        Task {
            do {
                let commit = try await store.gitCommit(path, message: msg)
                isCommitting = false
                commitMessage = ""
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if let commit {
                    ui.toast = "Committed: \(commit.short) \(commit.subject)"
                } else {
                    ui.toast = "Committed changes"
                }
                await loadStatus()
            } catch {
                isCommitting = false
                ui.toast = "Commit failed: \(error.localizedDescription)"
            }
        }
    }

    private func performPush() {
        guard !isPushing else { return }

        isPushing = true
        Task {
            do {
                _ = try await store.gitPush(path)
                isPushing = false
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                ui.toast = "Pushed changes to remote"
                await loadStatus()
            } catch {
                isPushing = false
                ui.toast = "Push failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Not a Git Repo View

    private var notAGitRepoView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 48))
                .foregroundStyle(Theme.tertiaryText)

            Text("Not a git repository")
                .font(Theme.sans(20, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("This directory is not configured as a git repository on your PC.")
                .font(Theme.sans(15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

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
                Task { await loadStatus() }
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

    // MARK: - Loading

    private func loadStatus() async {
        if status == nil {
            isLoading = true
        }
        errorMessage = nil
        do {
            let loaded = try await store.gitStatus(path)
            status = loaded
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Unified Diff Sheet

/// Unified diff sheet: coloured +/- lines, file headers bold
struct GitDiffSheet: View {
    let path: String
    let file: String?
    let status: String?

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var diffText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var sheetTitle: String {
        if let file {
            return URL(fileURLWithPath: file).lastPathComponent
        }
        return "Workspace diff"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(1.2)
                } else if let error = errorMessage {
                    diffErrorView(error)
                } else if diffText.isEmpty {
                    emptyDiffView
                } else {
                    diffScrollView
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !diffText.isEmpty {
                        Button {
                            UIPasteboard.general.string = diffText
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            ui.toast = "Diff copied"
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.text)
                        }
                        .accessibilityLabel("Copy diff")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
        .task {
            await loadDiff()
        }
    }

    private var diffScrollView: some View {
        let lines = diffText.components(separatedBy: "\n")

        return ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    diffLineView(line)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func diffLineView(_ line: String) -> some View {
        if line.hasPrefix("diff --git") || line.hasPrefix("index ") || line.hasPrefix("---") || line.hasPrefix("+++") {
            // File header: bold
            Text(line)
                .font(Theme.mono(13).bold())
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.04))
        } else if line.hasPrefix("@@") {
            // Hunk header: subtle tint
            Text(line)
                .font(Theme.mono(12).weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.accent.opacity(0.08))
        } else if line.hasPrefix("+") {
            // Added line: green
            Text(line)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.success)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.success.opacity(0.10))
        } else if line.hasPrefix("-") {
            // Removed line: red
            Text(line)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.danger.opacity(0.10))
        } else {
            // Unchanged line
            Text(line.isEmpty ? " " : line)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
        }
    }

    private var emptyDiffView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(Theme.tertiaryText)

            Text("No diff available")
                .font(Theme.sans(17, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("There are no staged or unstaged changes to display.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func diffErrorView(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Theme.danger)

            Text(error)
                .font(Theme.sans(14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                Task { await loadDiff() }
            } label: {
                Text("Retry")
                    .font(Theme.sans(14, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        }
    }

    private func loadDiff() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await store.gitDiff(path, file: file)
            diffText = result
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}
