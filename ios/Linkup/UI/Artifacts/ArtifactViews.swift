import AVKit
import Foundation
import SwiftUI
import WebKit

// MARK: - ArtifactCard

/// Inline card for an artifact or file produced by an agent.
///
/// Images are shown directly in the conversation as full-width previews with their title beneath.
/// Other artifacts (HTML, SVG, PDF, audio, video, code, text) appear as a rounded card with a 56×56
/// tile, title, and metadata subtitle. Tapping opens the full-screen `ArtifactViewer`.
struct ArtifactCard: View {
    let artifact: ArtifactRef

    @Environment(LinkupClient.self) private var client
    @Environment(UIState.self) private var ui

    @State private var shareItem: ArtifactShareFile?

    private var isImageKind: Bool {
        artifact.kind.lowercased() == "image" || (artifact.mime?.lowercased().hasPrefix("image/") ?? false)
    }

    var body: some View {
        Group {
            if isImageKind {
                imageCard
            } else {
                standardCard
            }
        }
        .sheet(item: $shareItem) { item in
            ArtifactShareSheet(items: [item.url])
        }
    }

    // MARK: - Image Layout (Large Inline)

    private var imageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImageView(url: artifact.url, onTap: {
                ui.openArtifact = artifact
            })
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )

            if !artifact.title.isEmpty {
                Text(artifact.title)
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ui.openArtifact = artifact
        }
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - Standard File / Artifact Layout

    private var standardCard: some View {
        HStack(spacing: 14) {
            tileView

            VStack(alignment: .leading, spacing: 4) {
                Text(artifact.title)
                    .font(Theme.sans(17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitleText)
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture {
            ui.openArtifact = artifact
        }
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - Tile Icon

    @ViewBuilder
    private var tileView: some View {
        switch artifact.kind.lowercased() {
        case "image":
            RemoteImageView(url: artifact.url, onTap: {
                ui.openArtifact = artifact
            })
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )

        case "html", "svg", "code":
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.artifactTile)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "square.on.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.text)
                )

        case "pdf":
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.elevated)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.text)
                )

        case "video":
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.elevated)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.text)
                )

        case "audio":
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.elevated)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.text)
                )

        case "markdown":
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.elevated)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.text)
                )

        default:
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.elevated)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "doc")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.text)
                )
        }
    }

    // MARK: - Subtitle

    private var subtitleText: String {
        switch artifact.kind.lowercased() {
        case "html", "svg":
            return "Artifact"
        case "image":
            if let size = artifact.size, size > 0 {
                return "Image · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            }
            return "Image"
        case "pdf":
            if let size = artifact.size, size > 0 {
                return "PDF · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            }
            return "PDF"
        case "video":
            if let size = artifact.size, size > 0 {
                return "Video · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            }
            return "Video"
        case "audio":
            if let size = artifact.size, size > 0 {
                return "Audio · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            }
            return "Audio"
        default:
            if let size = artifact.size, size > 0 {
                return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            }
            return artifact.kind.capitalized
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            ui.openArtifact = artifact
        } label: {
            Label("Open", systemImage: "arrow.up.right")
        }

        Button {
            Task {
                await shareArtifact()
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Button {
            copyLink()
        } label: {
            Label("Copy Link", systemImage: "link")
        }
    }

    private func shareArtifact() async {
        do {
            let dest = try await ArtifactDownloader.download(artifact: artifact, client: client)
            shareItem = ArtifactShareFile(url: dest)
        } catch {
            ui.toast = "Failed to download file"
        }
    }

    private func copyLink() {
        var link = artifact.url
        if let base = client.settings.baseURL, !link.hasPrefix("http") {
            var baseStr = base.absoluteString
            while baseStr.hasSuffix("/") { baseStr.removeLast() }
            let rel = link.hasPrefix("/") ? link : "/" + link
            link = baseStr + rel
        }
        if let comps = URLComponents(string: link) {
            var clean = comps
            clean.queryItems = comps.queryItems?.filter { $0.name.lowercased() != "token" }
            if clean.queryItems?.isEmpty == true { clean.queryItems = nil }
            link = clean.string ?? link
        }
        UIPasteboard.general.string = link
        ui.toast = "Link copied"
    }
}

// MARK: - ArtifactViewer

/// Full-screen cover for reviewing agent-produced artifacts and files.
///
/// Supports interactive WKWebView browsing for web/svg/pdf/markdown/code/documents,
/// zoomable/pannable media for images with swipe-to-dismiss, and AVPlayer for video/audio.
/// Controls use Apple Liquid Glass with an xmark dismiss button, centered title, and capsule share/reload.
struct ArtifactViewer: View {
    let artifact: ArtifactRef

    @Environment(LinkupClient.self) private var client
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var reloadTrigger = UUID()
    @State private var shareItem: ArtifactShareFile?
    @State private var isDownloadingForShare = false

    // Web view state
    @State private var webProgress: Double = 0
    @State private var isWebLoading = false
    @State private var webErrorMessage: String?

    private enum ViewerKind {
        case image
        case media
        case web
    }

    private var viewerKind: ViewerKind {
        let k = artifact.kind.lowercased()
        let m = artifact.mime?.lowercased() ?? ""
        if k == "image" || m.hasPrefix("image/") {
            return .image
        }
        if k == "video" || k == "audio" || m.hasPrefix("video/") || m.hasPrefix("audio/") {
            return .media
        }
        return .web
    }

    var body: some View {
        ZStack {
            viewerBackground
                .ignoresSafeArea()

            switch viewerKind {
            case .image:
                ZStack(alignment: .top) {
                    ArtifactZoomableImageView(
                        artifact: artifact,
                        reloadTrigger: reloadTrigger,
                        onDismiss: {
                            dismiss()
                            ui.openArtifact = nil
                        }
                    )

                    topBar
                        .safeAreaPadding(.top)
                }

            case .media:
                ZStack(alignment: .top) {
                    ArtifactMediaViewer(
                        url: client.resolve(artifact.url),
                        kind: artifact.kind,
                        title: artifact.title,
                        reloadTrigger: reloadTrigger
                    )

                    topBar
                        .safeAreaPadding(.top)
                }

            case .web:
                VStack(spacing: 0) {
                    topBar
                        .safeAreaPadding(.top)
                        .padding(.bottom, 6)

                    ZStack(alignment: .top) {
                        ArtifactWebView(
                            url: client.resolve(artifact.url),
                            progress: $webProgress,
                            isLoading: $isWebLoading,
                            errorMessage: $webErrorMessage,
                            reloadTrigger: reloadTrigger
                        )

                        if isWebLoading && webProgress > 0 && webProgress < 1.0 {
                            ArtifactProgressBar(progress: webProgress)
                        }

                        if let error = webErrorMessage {
                            webErrorView(error)
                        }
                    }
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ArtifactShareSheet(items: [item.url])
        }
    }

    private var viewerBackground: Color {
        Theme.background
    }

    // MARK: - Top Bar

    private var topBar: some View {
        GlassEffectContainer {
            ZStack {
                HStack {
                    SheetCloseButton {
                        dismiss()
                        ui.openArtifact = nil
                    }

                    Spacer()

                    HStack(spacing: 0) {
                        Button {
                            Task {
                                await shareFile()
                            }
                        } label: {
                            if isDownloadingForShare {
                                ProgressView()
                                    .tint(Theme.text)
                                    .scaleEffect(0.8)
                                    .frame(width: 42, height: 44)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .frame(width: 42, height: 44)
                            }
                        }
                        .disabled(isDownloadingForShare)

                        Divider()
                            .frame(height: 18)
                            .overlay(Theme.hairline)

                        Button {
                            reloadArtifact()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .frame(width: 42, height: 44)
                        }
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }

                Text(artifact.title)
                    .font(Theme.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 96)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Web Error View

    @ViewBuilder
    private func webErrorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Theme.danger)

            Text(error)
                .font(Theme.sans(15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                webErrorMessage = nil
                reloadTrigger = UUID()
            } label: {
                Text("Retry")
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Theme.elevated)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Actions

    private func shareFile() async {
        isDownloadingForShare = true
        defer { isDownloadingForShare = false }
        do {
            let dest = try await ArtifactDownloader.download(artifact: artifact, client: client)
            shareItem = ArtifactShareFile(url: dest)
        } catch {
            ui.toast = "Failed to download file"
        }
    }

    private func reloadArtifact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        webErrorMessage = nil
        reloadTrigger = UUID()
    }
}

// MARK: - RemoteImageView

/// Image loaded from the bridge with a shimmering placeholder and tap-to-zoom presentation.
struct RemoteImageView: View {
    let url: String
    var onTap: (() -> Void)? = nil

    @Environment(LinkupClient.self) private var client
    @Environment(UIState.self) private var ui

    var body: some View {
        Group {
            if let resolvedURL = client.resolve(url) {
                AsyncImage(url: resolvedURL) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.elevated)
                            .aspectRatio(16/9, contentMode: .fit)
                            .frame(minHeight: 120)
                            .overlay(ArtifactShimmer())
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        failurePlaceholder
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                failurePlaceholder
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let onTap {
                onTap()
            } else {
                ui.openArtifact = ArtifactRef(
                    id: url,
                    kind: "image",
                    title: "Image",
                    url: url,
                    path: nil,
                    mime: nil,
                    size: nil
                )
            }
        }
    }

    private var failurePlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 22))
            Text("Couldn't load image")
                .font(Theme.sans(12))
        }
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Zoomable Image Viewer

private struct ArtifactZoomableImageView: View {
    let artifact: ArtifactRef
    let reloadTrigger: UUID
    let onDismiss: () -> Void

    @Environment(LinkupClient.self) private var client

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var dismissOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background
                    .opacity(scale <= 1.05 ? max(0.2, 1.0 - Double(dismissOffset / 350.0)) : 1.0)
                    .ignoresSafeArea()

                if let resolvedURL = client.resolve(artifact.url) {
                    AsyncImage(url: resolvedURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(Theme.accent)
                                .scaleEffect(1.2)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                                .scaleEffect(scale)
                                .offset(y: scale <= 1.05 ? dismissOffset : panOffset.height)
                                .offset(x: scale > 1.05 ? panOffset.width : 0)
                                .gesture(
                                    SimultaneousGesture(
                                        MagnifyGesture()
                                            .onChanged { value in
                                                let newScale = lastScale * value.magnification
                                                scale = min(max(newScale, 0.8), 5.0)
                                            }
                                            .onEnded { _ in
                                                withAnimation(.snappy(duration: 0.25)) {
                                                    if scale < 1.0 {
                                                        scale = 1.0
                                                        lastScale = 1.0
                                                        panOffset = .zero
                                                        lastPanOffset = .zero
                                                    } else if scale > 4.5 {
                                                        scale = 4.5
                                                        lastScale = 4.5
                                                    } else {
                                                        lastScale = scale
                                                    }
                                                }
                                            },
                                        DragGesture()
                                            .onChanged { value in
                                                if scale > 1.05 {
                                                    panOffset = CGSize(
                                                        width: lastPanOffset.width + value.translation.width,
                                                        height: lastPanOffset.height + value.translation.height
                                                    )
                                                } else if value.translation.height > 0 {
                                                    dismissOffset = value.translation.height
                                                }
                                            }
                                            .onEnded { value in
                                                if scale > 1.05 {
                                                    lastPanOffset = panOffset
                                                } else {
                                                    if dismissOffset > 100 || value.predictedEndTranslation.height > 300 {
                                                        onDismiss()
                                                    } else {
                                                        withAnimation(.snappy(duration: 0.25)) {
                                                            dismissOffset = 0
                                                        }
                                                    }
                                                }
                                            }
                                    )
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation(.snappy(duration: 0.25)) {
                                        if scale > 1.05 {
                                            scale = 1.0
                                            lastScale = 1.0
                                            panOffset = .zero
                                            lastPanOffset = .zero
                                        } else {
                                            scale = 2.5
                                            lastScale = 2.5
                                        }
                                    }
                                }
                        case .failure:
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Theme.secondaryText)
                                Text("Couldn't load image")
                                    .font(Theme.sans(15))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .id(reloadTrigger)
                }
            }
        }
    }
}

// MARK: - AVPlayer Media Viewer

private struct ArtifactMediaViewer: View {
    let url: URL?
    let kind: String
    let title: String
    let reloadTrigger: UUID

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let player {
                if kind.lowercased() == "audio" {
                    VStack(spacing: 24) {
                        Image(systemName: "waveform")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 40)

                        Text(title)
                            .font(Theme.sans(18, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        VideoPlayer(player: player)
                            .frame(height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .bottom)
                }
            } else if url != nil {
                ProgressView()
                    .tint(Theme.accent)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.danger)
                    Text("Invalid media URL")
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
        .onChange(of: reloadTrigger) { _, _ in
            setupPlayer()
        }
    }

    private func setupPlayer() {
        guard let url else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVPlayer(url: url)
        player = p
        p.play()
    }
}

// MARK: - WKWebView UIViewRepresentable

private struct ArtifactWebView: UIViewRepresentable {
    let url: URL?
    @Binding var progress: Double
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let reloadTrigger: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0x1F / 255, green: 0x1E / 255, blue: 0x1D / 255, alpha: 1)
        webView.scrollView.backgroundColor = UIColor(red: 0x1F / 255, green: 0x1E / 255, blue: 0x1D / 255, alpha: 1)
        webView.scrollView.pinchGestureRecognizer?.isEnabled = true
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 5.0

        context.coordinator.startObserving(webView: webView)
        context.coordinator.currentURL = url

        if let url {
            webView.load(URLRequest(url: url))
        } else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid or unresolvable artifact URL"
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.lastReloadTrigger != reloadTrigger {
            context.coordinator.lastReloadTrigger = reloadTrigger
            if let url, context.coordinator.currentURL != url {
                context.coordinator.currentURL = url
                webView.load(URLRequest(url: url))
            } else {
                webView.reload()
            }
        } else if let url, context.coordinator.currentURL != url {
            context.coordinator.currentURL = url
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ArtifactWebView
        private var progressObservation: NSKeyValueObservation?
        var lastReloadTrigger: UUID?
        var currentURL: URL?

        init(_ parent: ArtifactWebView) {
            self.parent = parent
            super.init()
        }

        func startObserving(webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.parent.progress = wv.estimatedProgress
                    self.parent.isLoading = wv.isLoading
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                self.parent.isLoading = true
                self.parent.errorMessage = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.parent.isLoading = false
                self.parent.errorMessage = nil
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.parent.isLoading = false
                let nsError = error as NSError
                if nsError.code != NSURLErrorCancelled {
                    self.parent.errorMessage = error.localizedDescription
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.parent.isLoading = false
                let nsError = error as NSError
                if nsError.code != NSURLErrorCancelled {
                    self.parent.errorMessage = error.localizedDescription
                }
            }
        }

        deinit {
            progressObservation?.invalidate()
        }
    }
}

// MARK: - Progress Bar

private struct ArtifactProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.clear
                Theme.accent
                    .frame(width: geo.size.width * CGFloat(min(max(progress, 0.0), 1.0)), height: 2.5)
            }
        }
        .frame(height: 2.5)
    }
}

// MARK: - Shimmer Placeholder

private struct ArtifactShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            LinearGradient(
                colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: max(width, 80))
            .offset(x: phase * (width + 120))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
        }
        .clipped()
    }
}

// MARK: - Sharing Helpers

private struct ArtifactShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ArtifactShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

@MainActor
private enum ArtifactDownloader {
    static func download(artifact: ArtifactRef, client: LinkupClient) async throws -> URL {
        guard let remoteURL = client.resolve(artifact.url) else {
            throw BridgeError(message: "Invalid artifact URL")
        }
        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw BridgeError(message: "Download failed (status \(http.statusCode))")
        }
        var filename = artifact.title.trimmingCharacters(in: .whitespacesAndNewlines)
        filename = filename.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        if filename.isEmpty {
            filename = "artifact"
        }
        if !filename.contains(".") {
            let ext: String
            switch artifact.kind.lowercased() {
            case "image":
                ext = (artifact.mime?.contains("png") == true) ? "png" : "jpg"
            case "pdf": ext = "pdf"
            case "html": ext = "html"
            case "video": ext = "mp4"
            case "audio": ext = "m4a"
            case "markdown": ext = "md"
            default: ext = "dat"
            }
            filename += ".\(ext)"
        }
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: targetURL)
        try FileManager.default.moveItem(at: tempURL, to: targetURL)
        return targetURL
    }
}
