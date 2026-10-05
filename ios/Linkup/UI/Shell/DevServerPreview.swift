import SwiftUI
import WebKit

// MARK: - Dev Server Detector

/// Detects local development server URLs and port numbers in text and tool outputs.
public enum DevServerDetector {
    /// Extracts unique valid port numbers (1-65535) from localhost, 127.0.0.1, or 0.0.0.0 URLs in the given text.
    public static func ports(in text: String) -> [Int] {
        guard !text.isEmpty else { return [] }
        let pattern = #"(?:https?:\/\/)?(?:localhost|127\.0\.0\.1|0\.0\.0\.0):([0-9]{1,5})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        var result: [Int] = []
        var seen = Set<Int>()
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let portRange = match.range(at: 1)
            let portStr = nsString.substring(with: portRange)
            if let port = Int(portStr), port > 0, port <= 65535 {
                if !seen.contains(port) {
                    seen.insert(port)
                    result.append(port)
                }
            }
        }
        return result
    }
}

// MARK: - Web Controller

@MainActor
final class DevServerWebController: NSObject, ObservableObject {
    weak var webView: WKWebView?
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0.0
    @Published var pageTitle: String?
    @Published var currentURL: URL?
    @Published var errorMessage: String?

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        errorMessage = nil
        webView?.reload()
    }
}

// MARK: - WKWebView Representable

private struct DevServerWebView: UIViewRepresentable {
    let url: URL?
    @ObservedObject var controller: DevServerWebController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
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

        controller.webView = webView
        context.coordinator.startObserving(webView: webView)

        if let url {
            webView.load(URLRequest(url: url))
        } else {
            controller.errorMessage = "Unable to resolve proxy URL"
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: DevServerWebController
        private var observations: [NSKeyValueObservation] = []

        init(controller: DevServerWebController) {
            self.controller = controller
            super.init()
        }

        func startObserving(webView: WKWebView) {
            observations = [
                webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                    Task { @MainActor [weak self] in
                        self?.controller.canGoBack = wv.canGoBack
                    }
                },
                webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                    Task { @MainActor [weak self] in
                        self?.controller.canGoForward = wv.canGoForward
                    }
                },
                webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                    Task { @MainActor [weak self] in
                        self?.controller.isLoading = wv.isLoading
                    }
                },
                webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                    Task { @MainActor [weak self] in
                        self?.controller.progress = wv.estimatedProgress
                    }
                },
                webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                    Task { @MainActor [weak self] in
                        self?.controller.pageTitle = wv.title
                    }
                },
                webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                    Task { @MainActor [weak self] in
                        self?.controller.currentURL = wv.url
                    }
                }
            ]
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                self.controller.isLoading = true
                self.controller.errorMessage = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.controller.isLoading = false
                self.controller.errorMessage = nil
                self.controller.pageTitle = webView.title
                self.controller.currentURL = webView.url
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.controller.isLoading = false
                let nsError = error as NSError
                if nsError.code != NSURLErrorCancelled {
                    self.controller.errorMessage = error.localizedDescription
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.controller.isLoading = false
                let nsError = error as NSError
                if nsError.code != NSURLErrorCancelled {
                    self.controller.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - DevServerPreview View

/// Native browser preview for local dev servers reverse-proxied by the Linkup bridge.
public struct DevServerPreview: View {
    public let port: Int

    @Environment(LinkupClient.self) private var client
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @StateObject private var controller = DevServerWebController()

    public init(port: Int) {
        self.port = port
    }

    private var targetURL: URL? {
        client.resolve("/linkup/proxy/\(port)/")
    }

    public var body: some View {
        VStack(spacing: 0) {
            if controller.isLoading && controller.progress > 0 && controller.progress < 1.0 {
                ProgressView(value: controller.progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(height: 2)
            }

            ZStack {
                DevServerWebView(url: targetURL, controller: controller)
                    .ignoresSafeArea(edges: .bottom)

                if let error = controller.errorMessage {
                    errorStateView(error)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("localhost:\(port)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    ui.previewPort = nil
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .clipShape(Circle())
                .accessibilityLabel("Close preview")
            }

            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("localhost:\(port)")
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if let title = controller.pageTitle, !title.isEmpty {
                        Text(title)
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let url = controller.currentURL ?? targetURL {
                        openURL(url)
                    }
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .clipShape(Circle())
                .accessibilityLabel("Open in Safari")
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    controller.goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 16, weight: .medium))
                }
                .disabled(!controller.canGoBack)
                .accessibilityLabel("Back")

                Spacer()

                Button {
                    controller.goForward()
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 16, weight: .medium))
                }
                .disabled(!controller.canGoForward)
                .accessibilityLabel("Forward")

                Spacer()

                Button {
                    controller.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                }
                .accessibilityLabel("Reload")

                Spacer()

                Button {
                    if let url = controller.currentURL ?? targetURL {
                        openURL(url)
                    }
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 16, weight: .medium))
                }
                .accessibilityLabel("Open in Safari")
            }
        }
    }

    @ViewBuilder
    private func errorStateView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)

            Text("Cannot connect to port \(port)")
                .font(Theme.sans(18, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text(message)
                .font(Theme.sans(14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                controller.reload()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(Theme.sans(14, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
