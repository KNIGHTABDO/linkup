import SwiftUI

// MARK: - iPad Inspector Panel

/// Right-hand inspector panel for iPad displaying the turn summary timeline or the open artifact viewer.
struct InspectorView: View {
    var width: CGFloat = 380

    @Environment(UIState.self) private var ui

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.surface
                .ignoresSafeArea()

            Group {
                if let artifact = ui.openArtifact {
                    ArtifactViewer(artifact: artifact)
                        .id("\(ui.currentSessionId ?? "new")/\(artifact.url)")
                } else if let turn = ui.summaryTurn {
                    SummarySheet(turn: turn)
                        .id("\(ui.currentSessionId ?? "new")/\(turn.id)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // SummarySheet and ArtifactViewer close themselves with `dismiss`, which does nothing outside a
            // presentation. This transparent target sits exactly over their leading close button (44pt, no
            // larger, so it never covers header content) and clears the inspector state instead.
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    ui.summaryTurn = nil
                    ui.openArtifact = nil
                }
            } label: {
                Color.clear
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .padding(.top, 12)
            .accessibilityLabel("Close inspector")
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }
}
