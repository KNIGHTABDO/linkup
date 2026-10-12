import AVFoundation
import Foundation
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Download (any size, with progress, cached)

/// Streams an artifact to disk (never into memory, so multi-GB files are fine) and reports progress.
/// Finished files are kept in Caches/LinkupFiles/<id>/ so reopening or sharing is instant; iOS may purge them.
@MainActor
@Observable
final class ArtifactDownload {
    let artifact: ArtifactRef
    private(set) var received: Int64 = 0
    private(set) var total: Int64 = 0
    private(set) var fileURL: URL?
    private(set) var error: String?
    private(set) var isRunning = false

    @ObservationIgnored private var task: URLSessionDownloadTask?

    init(artifact: ArtifactRef) {
        self.artifact = artifact
        total = Int64(artifact.size ?? 0)
        let cached = Self.localURL(for: artifact)
        if FileManager.default.fileExists(atPath: cached.path) {
            fileURL = cached
        }
    }

    var fraction: Double { total > 0 ? min(1, Double(received) / Double(total)) : 0 }

    func start(client: LinkupClient) {
        guard fileURL == nil, !isRunning else { return }
        guard let remote = client.resolve(artifact.url) else {
            error = "Invalid file URL"
            return
        }
        error = nil
        received = 0
        isRunning = true
        let destination = Self.localURL(for: artifact)
        let delegate = DownloadDelegate(destination: destination) { [weak self] got, expected in
            Task { @MainActor in
                guard let self else { return }
                self.received = got
                if expected > 0 { self.total = expected }
            }
        } finished: { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = false
                self.task = nil
                switch result {
                case .success(let url): self.fileURL = url
                case .failure(let err):
                    if (err as? URLError)?.code != .cancelled {
                        self.error = (err as? BridgeError)?.message ?? err.localizedDescription
                    }
                }
            }
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60 * 6
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: remote)
        self.task = task
        task.resume()
        session.finishTasksAndInvalidate()
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Downloads (or reuses the cached copy) and returns the local file. Used by Share for every kind.
    static func file(for artifact: ArtifactRef, client: LinkupClient) async throws -> URL {
        let download = ArtifactDownload(artifact: artifact)
        if let url = download.fileURL { return url }
        download.start(client: client)
        while download.isRunning {
            try await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled {
                download.cancel()
                throw CancellationError()
            }
        }
        if let url = download.fileURL { return url }
        throw BridgeError(message: download.error ?? "Download failed")
    }

    static func localURL(for artifact: ArtifactRef) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinkupFiles", isDirectory: true)
            .appendingPathComponent(safe(artifact.id), isDirectory: true)
        return base.appendingPathComponent(fileName(for: artifact))
    }

    /// The title as a file name, with an extension from the served name or the MIME type so previews and
    /// "Save to Files" know the type.
    static func fileName(for artifact: ArtifactRef) -> String {
        var name = safe(artifact.title.trimmingCharacters(in: .whitespacesAndNewlines))
        if name.isEmpty { name = "file" }
        if (name as NSString).pathExtension.isEmpty {
            let served = ((artifact.url.split(separator: "?").first.map(String.init) ?? "") as NSString).pathExtension
            let ext = !served.isEmpty
                ? served
                : artifact.mime.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension } ?? ""
            if !ext.isEmpty { name += "." + ext }
        }
        return name
    }

    private static func safe(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let destination: URL
    let progress: (Int64, Int64) -> Void
    let finished: (Result<URL, Error>) -> Void
    private var outcome: Result<URL, Error>?
    private var lastReport = Date.distantPast

    init(destination: URL, progress: @escaping (Int64, Int64) -> Void,
         finished: @escaping (Result<URL, Error>) -> Void) {
        self.destination = destination
        self.progress = progress
        self.finished = finished
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        guard now.timeIntervalSince(lastReport) > 0.1 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastReport = now
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this returns: move it now.
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            outcome = .failure(BridgeError(message: "Download failed (status \(http.statusCode))"))
            return
        }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: location, to: destination)
            outcome = .success(destination)
        } catch {
            outcome = .failure(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finished(.failure(error))
        } else {
            finished(outcome ?? .failure(BridgeError(message: "Download failed")))
        }
    }
}

// MARK: - Any-file viewer

/// Viewer for files the web view can't show (archives, Office docs, models, binaries…): downloads with
/// progress, then previews with Quick Look when iOS can, otherwise offers Share / Save to Files.
struct ArtifactFileViewer: View {
    let artifact: ArtifactRef
    let reloadTrigger: UUID
    var onShare: (URL) -> Void

    @Environment(LinkupClient.self) private var client
    @State private var download: ArtifactDownload?

    var body: some View {
        Group {
            if let download {
                if let url = download.fileURL {
                    if QLPreviewController.canPreview(url as NSURL) {
                        QuickLookPreview(url: url)
                            .ignoresSafeArea(edges: .bottom)
                    } else {
                        fileCard(download) {
                            Button {
                                onShare(url)
                            } label: {
                                Label("Share or Save to Files", systemImage: "square.and.arrow.up")
                                    .font(Theme.sans(16, weight: .semibold))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(Theme.accent)
                            Text("No preview for this file type on iPhone.")
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                } else if let error = download.error {
                    fileCard(download) {
                        Text(error)
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                        Button("Retry") { download.start(client: client) }
                            .buttonStyle(.glass)
                    }
                } else {
                    fileCard(download) {
                        ProgressView(value: download.fraction)
                            .tint(Theme.accent)
                            .frame(maxWidth: 260)
                        Text(progressText(download))
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.secondaryText)
                            .contentTransition(.numericText())
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: begin)
        .onChange(of: reloadTrigger) { _, _ in
            download?.cancel()
            download = nil
            try? FileManager.default.removeItem(at: ArtifactDownload.localURL(for: artifact))
            begin()
        }
        .onDisappear { download?.cancel() }
    }

    private func begin() {
        if download == nil { download = ArtifactDownload(artifact: artifact) }
        download?.start(client: client)
    }

    private func progressText(_ d: ArtifactDownload) -> String {
        let got = ByteCountFormatter.string(fromByteCount: d.received, countStyle: .file)
        guard d.total > 0 else { return "Downloading… \(got)" }
        let all = ByteCountFormatter.string(fromByteCount: d.total, countStyle: .file)
        return "\(got) of \(all) · \(Int(d.fraction * 100))%"
    }

    @ViewBuilder
    private func fileCard<Content: View>(_ d: ArtifactDownload, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 22)
                .fill(Theme.elevated)
                .frame(width: 96, height: 96)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: Self.symbol(for: artifact))
                            .font(.system(size: 34, weight: .medium))
                        let ext = (artifact.title as NSString).pathExtension.uppercased()
                        if !ext.isEmpty {
                            Text(ext).font(Theme.sans(11, weight: .bold))
                        }
                    }
                    .foregroundStyle(Theme.text)
                )
            VStack(spacing: 4) {
                Text(artifact.title)
                    .font(Theme.sans(17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if d.total > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: d.total, countStyle: .file))
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            content()
        }
        .padding(.horizontal, 32)
    }

    static func symbol(for artifact: ArtifactRef) -> String {
        let ext = (artifact.title as NSString).pathExtension.lowercased()
        switch ext {
        case "zip", "tar", "gz", "tgz", "7z", "rar", "xz", "bz2": return "doc.zipper"
        case "doc", "docx", "pages", "rtf", "odt": return "doc.richtext"
        case "xls", "xlsx", "csv", "numbers", "ods": return "tablecells"
        case "ppt", "pptx", "key", "odp": return "rectangle.on.rectangle"
        case "usdz", "obj", "stl", "glb", "gltf": return "cube"
        case "ipa", "apk", "dmg", "exe", "deb", "appimage": return "shippingbox"
        case "ttf", "otf", "woff", "woff2": return "textformat"
        default: return "doc"
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Audio player

@MainActor
@Observable
final class AudioPlayerModel {
    let player: AVPlayer
    private(set) var isPlaying = false
    private(set) var current: Double = 0
    private(set) var duration: Double = 0
    private(set) var isBuffering = true
    private(set) var failed: String?
    var isScrubbing = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init(url: URL) {
        player = AVPlayer(url: url)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.isScrubbing { self.current = time.seconds.isFinite ? time.seconds : 0 }
                self.isBuffering = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.isPlaying = self.player.timeControlStatus != .paused
                if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 { self.duration = d }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.player.seek(to: .zero)
                self.current = 0
            }
        }
        statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            let message = item.status == .failed ? (item.error?.localizedDescription ?? "Can't play this file") : nil
            let ready = item.status == .readyToPlay
            Task { @MainActor in
                guard let self else { return }
                if let message { self.failed = message }
                if ready { self.isBuffering = false }
            }
        }
    }

    func toggle() {
        if player.timeControlStatus == .paused {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    func seek(to seconds: Double) {
        current = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(_ delta: Double) {
        seek(to: max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, current + delta)))
    }

    func scrub(to seconds: Double) { current = seconds }

    func tearDown() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        statusObservation?.invalidate()
        timeObserver = nil
        endObserver = nil
    }
}

/// Native audio player (play/pause, ±15 s, scrubber, times). Streams from the bridge with Range requests.
struct ArtifactAudioPlayer: View {
    let url: URL
    let title: String
    let size: Int?

    @State private var model: AudioPlayerModel?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.elevated)
                .frame(width: 160, height: 160)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.variableColor.iterative, isActive: model?.isPlaying == true)
                )

            VStack(spacing: 4) {
                Text(title)
                    .font(Theme.sans(18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let size, size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 24)

            if let model {
                if let failed = model.failed {
                    Text(failed)
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    controls(model)
                }
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard model == nil else { return }
            let m = AudioPlayerModel(url: url)
            model = m
            m.toggle()
        }
        .onDisappear {
            model?.tearDown()
            model = nil
        }
    }

    @ViewBuilder
    private func controls(_ model: AudioPlayerModel) -> some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { model.current }, set: { model.scrub(to: $0) }),
                in: 0...max(model.duration, 0.01),
                onEditingChanged: { editing in
                    model.isScrubbing = editing
                    if !editing { model.seek(to: model.current) }
                }
            )
            .tint(Theme.accent)
            .disabled(model.duration <= 0)

            HStack {
                Text(Self.time(model.current))
                Spacer()
                Text(model.duration > 0 ? "-" + Self.time(max(0, model.duration - model.current)) : "--:--")
            }
            .font(Theme.mono(12))
            .foregroundStyle(Theme.secondaryText)
            .monospacedDigit()
        }
        .padding(.horizontal, 32)

        GlassEffectContainer {
            HStack(spacing: 28) {
                Button { model.skip(-15) } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.glass)

                Button { model.toggle() } label: {
                    Group {
                        if model.isBuffering && model.isPlaying {
                            ProgressView().tint(Theme.text)
                        } else {
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: 76, height: 76)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

                Button { model.skip(15) } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.glass)
            }
            .foregroundStyle(Theme.text)
        }
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
