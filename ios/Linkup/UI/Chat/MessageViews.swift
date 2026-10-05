import SwiftUI

/// STUB (task chat): user bubble.
struct UserBubble: View {
    let message: UserMessage
    var body: some View { Text(message.text) }
}

/// STUB (task chat): one agent turn (activity row, text, artifacts, action row).
struct AssistantTurnView: View {
    let turn: AssistantTurn
    let sessionId: String
    var body: some View { Text(turn.textBlocks.map(\.text).joined()) }
}

/// STUB (task chat): streaming-safe markdown renderer in the serif agent voice.
struct MarkdownView: View {
    let text: String
    var isStreaming = false
    var body: some View { Text(text) }
}
