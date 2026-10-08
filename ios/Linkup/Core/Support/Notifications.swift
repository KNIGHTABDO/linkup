import Foundation

extension Notification.Name {
    /// Puts text into the composer (object: String). Posted by "Edit & resend".
    static let linkupComposerSetText = Notification.Name("LinkupComposerSetText")
    /// Focuses the sidebar search field (iPad ⌘K).
    static let linkupFocusSearch = Notification.Name("LinkupFocusSearch")
}
