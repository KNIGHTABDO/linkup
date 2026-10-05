import SwiftUI

// MARK: - iPad Inspector Panel

/// Right-hand inspector panel for iPad (380 pt) displaying
/// the turn summary timeline or the open artifact viewer.
struct InspectorView: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.surface
                .ignoresSafeArea()

            Group {
                if let artifact = ui.openArtifact {
                    ArtifactViewer(artifact: artifact)
                        .id(artifact.url)
                } else if let turn = ui.summaryTurn {
                    SummarySheet(turn: turn)
                        .id(turn.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Close button overlay for the inspector header:
            // Intercepts the top-left dismiss button on SummarySheet and ArtifactViewer,
            // guaranteeing that ui.summaryTurn and ui.openArtifact are cleared
            // with a smooth spring animation on iPad.
            Button {
                withAnimation(.smooth(duration: 0.35)) {
                    ui.summaryTurn = nil
                    ui.openArtifact = nil
                }
            } label: {
                Color.clear
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.top, 8)
            .accessibilityLabel("Close inspector")
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }
}
