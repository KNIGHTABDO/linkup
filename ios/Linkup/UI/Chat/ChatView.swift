import SwiftUI

/// STUB (task chat): the conversation (or the "Hello, night owl" new-chat screen when sessionId is nil).
struct ChatView: View {
    let sessionId: String?
    var body: some View { Text(sessionId ?? "New chat").foregroundStyle(Theme.text) }
}
