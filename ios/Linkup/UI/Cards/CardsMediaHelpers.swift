import AVKit
import SafariServices
import SwiftUI
import WebKit

// MARK: - Identifiable URL & In-App Safari

struct MediaIdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct MediaSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredBarTintColor = UIColor(Theme.surface)
        vc.preferredControlTintColor = UIColor(Theme.accent)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - URL Resolution

@MainActor
func mediaResolveURL(_ string: String?, client: LinkupClient? = nil) -> URL? {
    guard let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    if let client, let resolved = client.resolve(string) {
        return resolved
    }
    return URL(string: string)
}

// MARK: - Async Image & Placeholder

struct MediaAsyncImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Theme.elevated
                            .overlay(
                                ProgressView()
                                    .tint(Theme.secondaryText)
                                    .scaleEffect(0.7)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .failure:
                        MediaImagePlaceholder()
                    @unknown default:
                        MediaImagePlaceholder()
                    }
                }
            } else {
                MediaImagePlaceholder()
            }
        }
    }
}

struct MediaImagePlaceholder: View {
    var body: some View {
        Theme.elevated
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.tertiaryText)
            )
    }
}

// MARK: - Blurred Backdrop

struct MediaBackdrop: View {
    let url: URL?

    var body: some View {
        if let url {
            GeometryReader { geo in
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width + 32, height: geo.size.height + 40)
                            .blur(radius: 28)
                            .opacity(0.18)
                    }
                }
            }
            .padding(-16)
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - Expandable Summary

struct MediaExpandableSummary: View {
    let text: String
    var lineLimit: Int = 4

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(Theme.sans(14))
                .foregroundStyle(Theme.text)
                .lineSpacing(3)
                .lineLimit(isExpanded ? nil : lineLimit)
                .fixedSize(horizontal: false, vertical: true)

            if text.count > 160 {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show less" : "More")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Rating View

struct MediaRatingView: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)

            let isTenScale = rating > 5.0
            let scoreText = String(format: "%.1f", rating)
            let maxText = isTenScale ? "/10" : "/5"

            (Text(scoreText)
                .font(Theme.sans(12, weight: .bold))
                .foregroundStyle(Theme.text)
             + Text(" " + maxText)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.secondaryText))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.elevated, in: Capsule())
    }
}

// MARK: - Genre Chips

struct MediaGenreChips: View {
    let genres: [String]

    var body: some View {
        if !genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(genres, id: \.self) { genre in
                        Text(genre)
                            .font(Theme.sans(11, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.elevated, in: Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Formatters

enum MediaFormatters {
    static func formatDuration(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let str = value.string, !str.isEmpty {
            if str.contains(":") || str.contains("min") || str.contains("h") || str.contains("m") {
                return str
            }
        }
        if let totalSeconds = value.int, totalSeconds > 0 {
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                return String(format: "%d:%02d", minutes, seconds)
            }
        }
        return value.string
    }

    static func formatDate(_ dateString: String?) -> String? {
        guard let dateString, !dateString.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: dateString)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: dateString)
        }
        if date == nil {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            date = df.date(from: dateString)
        }
        guard let validDate = date else { return dateString }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return relative.localizedString(for: validDate, relativeTo: Date())
    }
}

// MARK: - YouTube & Video Playback

enum MediaYouTubeParser {
    static func extractID(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        let host = url.host?.lowercased() ?? ""

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let components = path.components(separatedBy: "/")
            if let first = components.first, !first.isEmpty {
                return first
            }
        }

        if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let items = comps.queryItems,
               let v = items.first(where: { $0.name == "v" })?.value,
               !v.isEmpty {
                return v
            }
            let pathComps = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if let shortsIdx = pathComps.firstIndex(of: "shorts"), shortsIdx + 1 < pathComps.count {
                return pathComps[shortsIdx + 1]
            }
            if let embedIdx = pathComps.firstIndex(of: "embed"), embedIdx + 1 < pathComps.count {
                return pathComps[embedIdx + 1]
            }
        }

        return nil
    }

    static func embedURL(for id: String) -> URL? {
        URL(string: "https://www.youtube-nocookie.com/embed/\(id)?playsinline=1&autoplay=1")
    }

    static func fallbackThumbnail(for id: String) -> URL? {
        URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
    }
}

struct MediaYouTubeWebView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .black

        if let embedURL = MediaYouTubeParser.embedURL(for: videoID) {
            webView.load(URLRequest(url: embedURL))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct MediaDirectVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(Theme.accent)
            }
        }
        .onAppear {
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

struct MediaInlineVideoView: View {
    let urlString: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black

            if let ytID = MediaYouTubeParser.extractID(from: urlString) {
                MediaYouTubeWebView(videoID: ytID)
            } else if let url = URL(string: urlString) {
                MediaDirectVideoPlayer(url: url)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.danger)
                    Text("Invalid video URL")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 28, height: 28)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(8)
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
