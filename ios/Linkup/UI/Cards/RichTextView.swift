import SwiftUI

/// Agent text with rich cards: markdown runs go to MarkdownView, ```linkup-card blocks to RichCardView.
struct RichTextView: View {
    let text: String
    var isStreaming = false

    var body: some View {
        let segments = CardExtractor.segments(text)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(segments) { segment in
                switch segment {
                case .markdown(let id, let md):
                    MarkdownView(text: md, isStreaming: isStreaming && id == segments.last?.id)
                case .card(_, let card):
                    RichCardView(card: card)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .pendingCard:
                    PendingCardView()
                case .invalidCard(_, let raw):
                    MarkdownView(text: "```json\n\(raw)\n```")
                }
            }
        }
        .animation(.smooth, value: segments.count)
    }
}
