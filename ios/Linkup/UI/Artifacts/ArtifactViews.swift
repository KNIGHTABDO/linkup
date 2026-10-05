import SwiftUI

/// STUB (task artifacts): inline card for an artifact/file (opens the viewer).
struct ArtifactCard: View {
    let artifact: ArtifactRef
    var body: some View { Text(artifact.title) }
}

/// STUB (task artifacts): full-screen viewer (HTML/SVG/PDF in a web view, images zoomable, files shareable).
struct ArtifactViewer: View {
    let artifact: ArtifactRef
    var body: some View { Text(artifact.title) }
}

/// STUB (task artifacts): bridge image (tool output / attachment) with tap-to-zoom.
struct RemoteImageView: View {
    let url: String
    var body: some View { Text(url) }
}
