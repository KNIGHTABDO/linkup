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

/// Resolves a card URL (relative bridge file or absolute). Only http(s) is ever returned, so a model-supplied
/// `javascript:` / `file:` string can never reach SFSafariViewController (which throws on other schemes).
@MainActor
func mediaResolveURL(_ string: String?, client: LinkupClient? = nil) -> URL? {
    guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    let url: URL?
    if let client, let resolved = client.resolve(trimmed) {
        url = resolved
    } else {
        url = URL(string: trimmed)
    }
    guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
    return url
}

// MARK: - Async Image & Placeholder

/// The container decides the size (a flexible colour), the image only fills it — so nothing jumps when it loads.
struct MediaAsyncImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        Theme.elevated
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                        case .empty:
                            ProgressView()
                                .tint(Theme.secondaryText)
                                .scaleEffect(0.7)
                        default:
                            MediaImagePlaceholder()
                        }
                    }
                } else {
                    MediaImagePlaceholder()
                }
            }
            .clipped()
            .accessibilityHidden(true)
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
            .accessibilityHidden(true)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - Link button

/// Solid pill (glass is for floating controls only, not card content) with a 44pt tap target.
struct MediaLinkButton: View {
    let title: String
    var symbol: String = "arrow.up.right"
    var tint: Color = Theme.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(Theme.sans(13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Theme.elevated, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Expandable Summary

struct MediaExpandableSummary: View {
    let text: String
    var lineLimit: Int = 4

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(Theme.sans(15))
                .foregroundStyle(Theme.text)
                .lineSpacing(3)
                .lineLimit(isExpanded ? nil : lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .cardParagraph(text)

            if text.count > 160 {
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show less" : "More")
                        .font(Theme.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Collapses the text" : "Shows the full text")
            }
        }
    }
}

// MARK: - Rating View

struct MediaRatingView: View {
    let rating: Double

    var body: some View {
        if rating.isFinite, rating > 0, rating <= 10 {
            let maxValue = rating > 5 ? 10 : 5
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(cardStarColor)

                (Text(rating.formatted(.number.precision(.fractionLength(1))))
                    .font(Theme.sans(13, weight: .bold))
                    .foregroundStyle(Theme.text)
                 + Text(" /\(maxValue)")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.secondaryText))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.elevated, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rated \(rating.formatted(.number.precision(.fractionLength(1)))) out of \(maxValue)")
        }
    }
}

// MARK: - Genre Chips

struct MediaGenreChips: View {
    let genres: [String]

    var body: some View {
        if !genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(genres.enumerated()), id: \.offset) { _, genre in
                        Text(genre)
                            .font(Theme.sans(12, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
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
    /// Seconds (number or numeric string) become "m:ss" / "h:mm:ss"; free text such as "2h 15m" is shown as written.
    static func formatDuration(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        var seconds: Double?
        if case .number(let n) = value {
            seconds = n
        } else if let str = value.string?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
            seconds = Double(str)
            if seconds == nil { return str }
        }
        guard let seconds, let total = cardSafeInt(seconds), total > 0 else { return nil }
        let duration = Duration.seconds(total)
        if total >= 3600 {
            return duration.formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1)))
        }
        return duration.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
    }

    static func formatDate(_ dateString: String?) -> String? {
        guard let dateString = dateString?.trimmingCharacters(in: .whitespacesAndNewlines), !dateString.isEmpty else { return nil }
        guard let date = CardDates.parse(dateString) else { return dateString }
        return CardDates.formatRelative(date)
    }
}

// MARK: - YouTube & Video Playback

enum MediaYouTubeParser {
    /// Video ids are 11 chars of [A-Za-z0-9_-]; anything else is rejected so it can never be spliced into the embed URL.
    private static func valid(_ id: String) -> String? {
        guard !id.isEmpty, id.count <= 20,
              id.unicodeScalars.allSatisfy({ ($0.value < 128) && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-") })
        else { return nil }
        return id
    }

    static func extractID(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        let host = url.host?.lowercased() ?? ""

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let first = path.components(separatedBy: "/").first, let id = valid(first) {
                return id
            }
        }

        if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let v = comps.queryItems?.first(where: { $0.name == "v" })?.value,
               let id = valid(v) {
                return id
            }
            let pathComps = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            for marker in ["shorts", "embed", "live"] {
                if let idx = pathComps.firstIndex(of: marker), idx + 1 < pathComps.count, let id = valid(pathComps[idx + 1]) {
                    return id
                }
            }
        }

        return nil
    }

    static func embedURL(for id: String) -> URL? {
        guard let id = valid(id) else { return nil }
        return URL(string: "https://www.youtube-nocookie.com/embed/\(id)?playsinline=1&autoplay=1")
    }

    static func fallbackThumbnail(for id: String) -> URL? {
        guard let id = valid(id) else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
    }

    /// True when the inline player can actually play it (YouTube, or a direct media file); other pages open in the browser.
    static func canPlayInline(_ urlString: String) -> Bool {
        if extractID(from: urlString) != nil { return true }
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return ["mp4", "m4v", "mov", "m3u8"].contains(url.pathExtension.lowercased())
    }
}

struct MediaYouTubeWebView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

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

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
    }
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
            guard player == nil else { return }
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
            } else if let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close video")
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
