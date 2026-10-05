import SwiftUI
import UIKit
import SafariServices
import Contacts
import ContactsUI
import AVFoundation

// MARK: - Remote Image View

struct DoRemoteImageView: View {
    let urlString: String?
    var contentMode: ContentMode = .fill

    @Environment(LinkupClient.self) private var client

    private var targetURL: URL? {
        guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else { return nil }
        if let resolved = client.resolve(urlString) {
            return resolved
        }
        return URL(string: urlString)
    }

    var body: some View {
        if let targetURL {
            AsyncImage(url: targetURL) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Theme.elevated)
                        .overlay(
                            ProgressView()
                                .tint(Theme.secondaryText)
                                .scaleEffect(0.8)
                        )
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                case .failure:
                    placeholderView(symbol: "photo")
                @unknown default:
                    Rectangle().fill(Theme.elevated)
                }
            }
        } else {
            placeholderView(symbol: "photo")
        }
    }

    private func placeholderView(symbol: String) -> some View {
        Rectangle()
            .fill(Theme.elevated)
            .overlay(
                Image(systemName: symbol)
                    .font(Theme.sans(20))
                    .foregroundStyle(Theme.tertiaryText)
            )
    }
}

// MARK: - Safari Sheet

struct DoSafariSheet: UIViewControllerRepresentable {
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

// MARK: - Contacts UI Sheet

struct DoContactSheet: UIViewControllerRepresentable {
    let contact: CNContact
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = CNContactViewController(forNewContact: contact)
        vc.delegate = context.coordinator
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.tintColor = UIColor(Theme.accent)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let parent: DoContactSheet
        init(_ parent: DoContactSheet) { self.parent = parent }

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            parent.isPresented = false
            viewController.dismiss(animated: true)
        }
    }
}

// MARK: - Speech Manager

@MainActor
final class DoSpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = DoSpeechManager()
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, languageCode: String?) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if let lang = languageCode, let voice = resolveVoice(for: lang) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func resolveVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let voice = AVSpeechSynthesisVoice(language: trimmed) {
            return voice
        }
        let map: [String: String] = [
            "en": "en-US", "english": "en-US",
            "es": "es-ES", "spanish": "es-ES",
            "fr": "fr-FR", "french": "fr-FR",
            "de": "de-DE", "german": "de-DE",
            "it": "it-IT", "italian": "it-IT",
            "ja": "ja-JP", "japanese": "ja-JP",
            "ko": "ko-KR", "korean": "ko-KR",
            "zh": "zh-CN", "chinese": "zh-CN",
            "ar": "ar-SA", "arabic": "ar-SA",
            "pt": "pt-BR", "portuguese": "pt-BR",
            "ru": "ru-RU", "russian": "ru-RU",
            "nl": "nl-NL", "dutch": "nl-NL",
            "tr": "tr-TR", "turkish": "tr-TR",
            "hi": "hi-IN", "hindi": "hi-IN",
            "pl": "pl-PL", "polish": "pl-PL",
            "sv": "sv-SE", "swedish": "sv-SE"
        ]
        if let bcp47 = map[trimmed] {
            return AVSpeechSynthesisVoice(language: bcp47)
        }
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        return allVoices.first(where: { $0.language.lowercased().hasPrefix(trimmed) })
    }
}

// MARK: - Color Hex Helper

enum DoColorHelper {
    static func parseHex(_ hexString: String) -> Color? {
        var clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.count == 3 || clean.count == 6 || clean.count == 8 else {
            return nil
        }
        if clean.count == 3 {
            clean = clean.map { "\($0)\($0)" }.joined()
        }
        var rgbValue: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&rgbValue) else { return nil }

        if clean.count == 6 {
            let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
            let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
            let b = Double(rgbValue & 0x0000FF) / 255.0
            return Color(red: r, green: g, blue: b)
        } else if clean.count == 8 {
            let r = Double((rgbValue & 0xFF000000) >> 24) / 255.0
            let g = Double((rgbValue & 0x00FF0000) >> 16) / 255.0
            let b = Double((rgbValue & 0x0000FF00) >> 8) / 255.0
            let a = Double(rgbValue & 0x000000FF) / 255.0
            return Color(red: r, green: g, blue: b).opacity(a)
        }
        return nil
    }
}

// MARK: - Format Helper

enum DoFormatHelper {
    static func formatBytes(_ bytes: Int) -> String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Recipe Cook Mode Sheet

struct DoCookModeSheet: View {
    let title: String
    let steps: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(Theme.sans(14, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 36, height: 36)
                            .background(Theme.surface, in: Circle())
                            .overlay(Circle().stroke(Theme.hairline))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text("Cook Mode")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.secondaryText)
                    }

                    Spacer()

                    Text("Step \(currentStep + 1) of \(steps.count)")
                        .font(Theme.sans(13, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.elevated, in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Progress Bar
                GeometryReader { proxy in
                    let stepRatio = steps.isEmpty ? 0 : CGFloat(currentStep + 1) / CGFloat(steps.count)
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.elevated)
                            .frame(height: 3)
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: proxy.size.width * stepRatio, height: 3)
                            .animation(.smooth, value: currentStep)
                    }
                }
                .frame(height: 3)

                // Large Step Text
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("STEP \(currentStep + 1)")
                                .font(Theme.sans(14, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .tracking(1.2)
                            Spacer()
                        }

                        if steps.indices.contains(currentStep) {
                            Text(steps[currentStep])
                                .font(Theme.serif(26, weight: .medium))
                                .foregroundStyle(Theme.text)
                                .lineSpacing(8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(28)
                }

                Spacer()

                // Bottom Navigation Bar
                HStack(spacing: 16) {
                    Button {
                        if currentStep > 0 {
                            withAnimation(.snappy) {
                                currentStep -= 1
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                            Text("Previous")
                        }
                        .font(Theme.sans(15, weight: .medium))
                        .foregroundStyle(currentStep > 0 ? Theme.text : Theme.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))
                    }
                    .disabled(currentStep == 0)
                    .buttonStyle(.plain)

                    Button {
                        if currentStep < steps.count - 1 {
                            withAnimation(.snappy) {
                                currentStep += 1
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } else {
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(currentStep < steps.count - 1 ? "Next" : "Done")
                            Image(systemName: currentStep < steps.count - 1 ? "chevron.right" : "checkmark")
                        }
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

// MARK: - Gallery Pager and Zoom

struct DoGalleryItem: Identifiable, Hashable {
    let id: String
    let url: String
    let caption: String?
}

enum DoGalleryExtractor {
    static func extractItems(from card: JSONValue) -> [DoGalleryItem] {
        if let objects = card["images"]?.array {
            var items: [DoGalleryItem] = []
            for (idx, obj) in objects.enumerated() {
                if let url = obj["url"]?.string, !url.isEmpty {
                    items.append(DoGalleryItem(id: "\(idx)_\(url)", url: url, caption: obj["caption"]?.string))
                } else if let s = obj.string, !s.isEmpty {
                    items.append(DoGalleryItem(id: "\(idx)_\(s)", url: s, caption: nil))
                }
            }
            if !items.isEmpty { return items }
        }
        return []
    }
}

struct DoZoomableImageView: View {
    let urlString: String

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DoRemoteImageView(urlString: urlString, contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newScale = lastScale * value
                                scale = max(1.0, min(newScale, 4.0))
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= 1.0 {
                                    withAnimation(.smooth) {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1.0 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                guard scale > 1.0 else { return }
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct DoGalleryViewerSheet: View {
    let images: [DoGalleryItem]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0

    init(images: [DoGalleryItem], initialIndex: Int) {
        self.images = images
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(Theme.sans(15, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("\(currentIndex + 1) of \(images.count)")
                        .font(Theme.sans(14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.18), in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Page View
                TabView(selection: $currentIndex) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                        DoZoomableImageView(urlString: item.url)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Caption
                if images.indices.contains(currentIndex),
                   let caption = images[currentIndex].caption, !caption.isEmpty {
                    Text(caption)
                        .font(Theme.sans(14))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.6))
                }
            }
        }
    }
}

// MARK: - Checklist Content View

struct DoChecklistItem: Identifiable, Hashable {
    let id: Int
    let text: String
    let initialDone: Bool
}

struct DoChecklistContentView: View {
    let card: JSONValue
    let title: String
    let items: [DoChecklistItem]
    let storageKey: String

    @AppStorage private var storedChecked: String
    @State private var checkedIds: Set<Int> = []

    init(card: JSONValue, title: String, items: [DoChecklistItem], storageKey: String) {
        self.card = card
        self.title = title
        self.items = items
        self.storageKey = storageKey
        self._storedChecked = AppStorage(wrappedValue: "", storageKey)
    }

    var body: some View {
        CardContainer(title: "Checklist", symbol: "checklist") {
            VStack(alignment: .leading, spacing: 14) {
                // Header with title and progress
                VStack(alignment: .leading, spacing: 8) {
                    if !title.isEmpty {
                        Text(title)
                            .font(Theme.sans(17, weight: .bold))
                            .foregroundStyle(Theme.text)
                    }

                    if !items.isEmpty {
                        HStack {
                            Text("\(checkedIds.count) of \(items.count) completed")
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(Theme.sans(12, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }

                        // Progress Bar
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Theme.elevated)
                                    .frame(height: 6)
                                Capsule()
                                    .fill(Theme.accent)
                                    .frame(width: max(0, proxy.size.width * progress), height: 6)
                                    .animation(.smooth, value: progress)
                            }
                        }
                        .frame(height: 6)
                    }
                }

                // Items List
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        let isDone = checkedIds.contains(item.id)
                        Button {
                            toggleItem(item.id)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                    .font(Theme.sans(18))
                                    .foregroundStyle(isDone ? Theme.accent : Theme.secondaryText)
                                    .contentTransition(.symbolEffect(.replace))

                                Text(item.text)
                                    .font(Theme.sans(15))
                                    .foregroundStyle(isDone ? Theme.secondaryText : Theme.text)
                                    .strikethrough(isDone, color: Theme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isDone ? Theme.elevated.opacity(0.4) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            loadInitialState()
        }
    }

    private var progress: CGFloat {
        guard !items.isEmpty else { return 0 }
        return CGFloat(checkedIds.count) / CGFloat(items.count)
    }

    private func loadInitialState() {
        if storedChecked.hasPrefix("v1:") {
            let payload = storedChecked.dropFirst(3)
            let ids = payload.split(separator: ",").compactMap { Int($0) }
            checkedIds = Set(ids)
        } else {
            let defaults = items.filter(\.initialDone).map(\.id)
            checkedIds = Set(defaults)
            saveState()
        }
    }

    private func toggleItem(_ id: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy) {
            if checkedIds.contains(id) {
                checkedIds.remove(id)
            } else {
                checkedIds.insert(id)
            }
        }
        saveState()
    }

    private func saveState() {
        storedChecked = "v1:" + checkedIds.map(String.init).joined(separator: ",")
    }
}
