import SwiftUI

/// STUB (task shell): drawer sidebar + chat, sheets for settings / connect / usage / model picker.
struct RootView: View {
    @Environment(UIState.self) private var ui
    var body: some View {
        ChatView(sessionId: ui.currentSessionId)
            .background(Theme.background.ignoresSafeArea())
    }
}
