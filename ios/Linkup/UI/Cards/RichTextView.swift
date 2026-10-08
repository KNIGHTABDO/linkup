import SwiftUI

/// Holds the newest streamed text so a delayed flush never renders a stale capture.
private final class LatestTextBox {
    var value = ""
}

/// Agent text with rich cards: markdown runs are rendered as blocks, ```linkup-card fences as RichCardView.
/// While streaming, rendering is throttled (~40 ms) and always ends on the newest text. The segment split and
/// the markdown parse (cached by text) therefore run once per throttled update, not once per token.
struct RichTextView: View {
    let text: String
    var isStreaming = false
    /// False for plain markdown (file viewer, fenced JSON): skips the card extractor entirely.
    var parseCards = true

    @State private var shown: [RichSegment]?
    @State private var lastRender = Date.distantPast
    @State private var flush: Task<Void, Never>?
    @State private var latest = LatestTextBox()

    private static let throttle: TimeInterval = 0.04

    private static func makeSegments(_ text: String, parseCards: Bool) -> [RichSegment] {
        parseCards ? CardExtractor.segments(text) : [.markdown(id: 0, text)]
    }

    private var segments: [RichSegment] {
        shown ?? Self.makeSegments(text, parseCards: parseCards)
    }

    var body: some View {
        let segments = self.segments
        let lastId = segments.last?.id
        let cardCount = segments.reduce(0) { count, seg in
            if case .card = seg { return count + 1 }
            return count
        }

        VStack(alignment: .leading, spacing: 14) {
            ForEach(segments) { segment in
                switch segment {
                case .markdown(let id, let md):
                    let live = isStreaming && id == lastId
                    ChatBlocksView(blocks: ChatMarkdownParser.parseCached(md, streaming: live), showCaret: live)
                case .card(_, let card):
                    RichCardView(card: card)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .pendingCard:
                    PendingCardView(isLive: isStreaming)
                case .invalidCard(_, let raw):
                    ChatBlocksView(blocks: ChatMarkdownParser.parseCached("````json\n\(raw)\n````"))
                }
            }
            if segments.isEmpty && isStreaming {
                ChatBlinkingCaret()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        // Only card insertions animate; token growth and pending-card resolution do not.
        .animation(.smooth, value: cardCount)
        .onAppear {
            latest.value = text
            if shown == nil { shown = Self.makeSegments(text, parseCards: parseCards) }
            lastRender = Date()
        }
        .onChange(of: text) { _, newText in
            latest.value = newText
            schedule()
        }
        .onChange(of: isStreaming) { _, streaming in
            if !streaming {
                latest.value = text
                renderNow()
            }
        }
        .onDisappear {
            flush?.cancel()
            flush = nil
        }
    }

    private func renderNow() {
        flush?.cancel()
        flush = nil
        lastRender = Date()
        shown = Self.makeSegments(latest.value, parseCards: parseCards)
    }

    private func schedule() {
        guard isStreaming else { renderNow(); return }
        let elapsed = Date().timeIntervalSince(lastRender)
        if elapsed >= Self.throttle {
            renderNow()
        } else if flush == nil {
            let delay = max(0.005, Self.throttle - elapsed)
            let box = latest
            let cards = parseCards
            flush = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { return }
                flush = nil
                lastRender = Date()
                // Read the box at flush time: it always holds the newest text, never the one captured at schedule time.
                shown = Self.makeSegments(box.value, parseCards: cards)
            }
        }
    }
}
