import SwiftUI

/// Settings → Updates: version check, SideStore install, and one-tap "add source" for SideStore-side updates.
struct UpdatesSection: View {
    @Environment(UpdateChecker.self) private var updates
    @Environment(\.openURL) private var openURL
    @State private var message: String?
    @State private var isInstalling = false
    @State private var isAddingSource = false

    var body: some View {
        Section {
            if let release = updates.available {
                Button {
                    guard !isInstalling else { return }
                    isInstalling = true
                    message = nil
                    Task {
                        defer { isInstalling = false }
                        if !(await updates.install(release)) {
                            message = "SideStore isn't installed. Opened the release page instead."
                            openURL(release.pageURL)
                        } else {
                            message = "Opening SideStore to install Linkup \(release.version)..."
                        }
                    }
                } label: {
                    HStack {
                        Label("Install \(release.version) with SideStore", systemImage: "arrow.down.circle.fill")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.accent)
                        if isInstalling {
                            Spacer()
                            ProgressView()
                                .tint(Theme.accent)
                        }
                    }
                }
                .disabled(isInstalling)
                .listRowBackground(Theme.elevated)

                if !release.notes.isEmpty {
                    Text(release.notes)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(6)
                        .listRowBackground(Theme.elevated)
                }
            }

            Button {
                message = nil
                Task { await updates.check() }
            } label: {
                HStack {
                    Text("Check for Updates")
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    statusView
                }
            }
            .disabled(updates.status == .checking)
            .listRowBackground(Theme.elevated)

            Button {
                guard !isAddingSource else { return }
                isAddingSource = true
                message = nil
                Task {
                    defer { isAddingSource = false }
                    if !(await updates.addSourceToSideStore()) {
                        message = "SideStore isn't installed."
                    } else {
                        message = "Linkup source added to SideStore."
                    }
                }
            } label: {
                HStack {
                    Text("Add Linkup Source to SideStore")
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.accent)
                    if isAddingSource {
                        Spacer()
                        ProgressView()
                            .tint(Theme.accent)
                    }
                }
            }
            .disabled(isAddingSource)
            .listRowBackground(Theme.elevated)
        } header: {
            Text("Updates")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        } footer: {
            Text(message ?? "With the source added, SideStore lists new Linkup versions and updates it from its own Updates screen. Your chats, settings and pairing are kept.")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch updates.status {
        case .checking:
            ProgressView()
                .tint(Theme.secondaryText)
        case .upToDate:
            Text("Up to date")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.secondaryText)
        case .failed(let reason):
            Text(reason)
                .font(Theme.sans(14))
                .foregroundStyle(Theme.danger)
                .lineLimit(1)
        case .idle:
            if updates.available != nil {
                Text("Update available")
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
