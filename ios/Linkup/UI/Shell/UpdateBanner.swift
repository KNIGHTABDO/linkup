import SwiftUI
import UIKit

/// Floating glass capsule announcing a newer release; tap installs through SideStore, × hides it for that version.
struct UpdateBanner: View {
    let release: UpdateChecker.Release

    @Environment(UpdateChecker.self) private var updates
    @Environment(UIState.self) private var ui
    @Environment(\.openURL) private var openURL
    @State private var isInstalling = false

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    guard !isInstalling else { return }
                    isInstalling = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task {
                        defer { isInstalling = false }
                        if !(await updates.install(release)) {
                            ui.toast = "SideStore not found. Opening the release page."
                            openURL(release.pageURL)
                        } else {
                            ui.toast = "Opening SideStore to install Linkup \(release.version)..."
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isInstalling {
                            ProgressView()
                                .tint(Theme.accent)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Text("Linkup \(release.version) available")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(isInstalling ? "Updating…" : "Update")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .disabled(isInstalling)

                Button {
                    withAnimation(.smooth) { updates.dismissBanner() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Dismiss update banner")
            }
        }
    }
}
