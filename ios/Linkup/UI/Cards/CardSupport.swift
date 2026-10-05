import SwiftUI

/// What a card can do back to the conversation (poll votes, quiz answers, "tell me more"…).
struct CardActions {
    /// Sends a message as the user in the current session.
    var send: (String) -> Void = { _ in }
}

private struct CardActionsKey: EnvironmentKey {
    static let defaultValue = CardActions()
}

extension EnvironmentValues {
    var cardActions: CardActions {
        get { self[CardActionsKey.self] }
        set { self[CardActionsKey.self] = newValue }
    }
}

/// Common chrome for every rich card: rounded surface, hairline border, optional header.
struct CardContainer<Content: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: symbol ?? "square.grid.2x2")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
    }
}

extension JSONValue {
    /// `card.strings("ingredients")`
    func strings(_ key: String) -> [String] { self[key]?.array?.compactMap(\.string) ?? [] }
    func objects(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }
    func url(_ key: String) -> URL? { self[key]?.string.flatMap { URL(string: $0) } }
}

/// Placeholder while a card is still streaming in.
struct PendingCardView: View {
    @State private var on = false
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.surface)
            .frame(height: 120)
            .overlay(ProgressView().tint(Theme.secondaryText))
            .opacity(on ? 1 : 0.6)
            .animation(.easeInOut(duration: 0.9).repeatForever(), value: on)
            .onAppear { on = true }
    }
}
