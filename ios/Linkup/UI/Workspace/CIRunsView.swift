import SwiftUI

/// Builds panel displaying GitHub Actions CI runs:
/// - Workflow name, title, branch, status icon, relative date
/// - Tap opens the run URL in `SFSafariViewController`
/// - Auto-refresh every 20 s while visible if any run is in progress
struct CIRunsView: View {
    let path: String

    @Environment(SessionStore.self) private var store

    @State private var runs: [CIRun] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var safariTarget: WorkspaceIdentifiableURL?

    private struct WorkspaceIdentifiableURL: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            if isLoading && runs.isEmpty {
                ProgressView()
                    .tint(Theme.accent)
                    .scaleEffect(1.2)
            } else if let error = errorMessage, runs.isEmpty {
                errorView(error)
            } else if runs.isEmpty {
                emptyRunsView
            } else {
                listView
            }
        }
        .task {
            await loadRuns()
            // Auto-refresh every 20s if any run is queued or in progress
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { break }
                let anyActive = runs.contains { run in
                    let s = run.status?.lowercased() ?? ""
                    return s == "in_progress" || s == "queued" || s == "waiting" || run.conclusion == nil
                }
                if anyActive {
                    await loadRuns()
                }
            }
        }
        .refreshable {
            await loadRuns()
        }
        .sheet(item: $safariTarget) { target in
            WorkspaceSafariView(url: target.url)
                .ignoresSafeArea()
        }
    }

    // MARK: - List View

    private var listView: some View {
        List {
            Section {
                ForEach(runs) { run in
                    Button {
                        openRun(run)
                    } label: {
                        runRow(run)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.hairline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    // MARK: - Run Row

    private func runRow(_ run: CIRun) -> some View {
        HStack(spacing: 12) {
            statusIcon(run)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(run.name ?? "Workflow")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)

                    if let branch = run.branch, !branch.isEmpty {
                        Text("on")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.tertiaryText)

                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10))
                            Text(branch)
                                .font(Theme.sans(11, weight: .medium))
                        }
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    }
                }

                Text(run.title ?? "Run #\(run.id)")
                    .font(Theme.sans(17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                if let created = run.created {
                    Text(WorkspaceFormatters.relative(timestamp: created))
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            Spacer()

            if run.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusIcon(_ run: CIRun) -> some View {
        let status = run.status?.lowercased() ?? ""
        let conclusion = run.conclusion?.lowercased() ?? ""

        if status == "in_progress" {
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(0.85)
        } else if status == "queued" || status == "waiting" {
            Image(systemName: "clock.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.orange)
        } else if conclusion == "success" {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.success)
        } else if conclusion == "failure" || conclusion == "timed_out" {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.danger)
        } else if conclusion == "cancelled" || conclusion == "skipped" {
            Image(systemName: "slash.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.secondaryText)
        } else {
            Image(systemName: "circle.dashed")
                .font(.system(size: 18))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func openRun(_ run: CIRun) {
        guard let urlString = run.url, let url = URL(string: urlString) else { return }
        safariTarget = WorkspaceIdentifiableURL(url: url)
    }

    // MARK: - Empty & Error Views

    private var emptyRunsView: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 44))
                .foregroundStyle(Theme.tertiaryText)

            Text("No CI runs")
                .font(Theme.sans(18, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("No GitHub Actions workflow runs found for this project.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
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
                Task { await loadRuns() }
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

    private func loadRuns() async {
        if runs.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        do {
            let loaded = try await store.ciRuns(path)
            runs = loaded
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}
