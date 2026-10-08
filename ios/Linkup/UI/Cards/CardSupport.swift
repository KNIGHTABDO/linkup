import SwiftUI

/// What a card can do back to the conversation (poll votes, quiz answers, "tell me more"…).
/// Equatable by `id` (the session id), so rebuilding it per body does not invalidate the environment.
struct CardActions: Equatable {
    /// Identity of the conversation the actions belong to; two values with the same id behave the same.
    var id: String = ""
    /// Sends a message as the user in the current session.
    var send: (String) -> Void = { _ in }

    static func == (lhs: CardActions, rhs: CardActions) -> Bool { lhs.id == rhs.id }
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

/// Placeholder while a card is still streaming in. If the card never completes (the turn ended or was stopped
/// mid-card) it settles into a quiet "Card incomplete" note instead of pulsing forever.
struct PendingCardView: View {
    /// False once the surrounding turn is finished: stop pulsing and say so.
    var isLive = true

    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.surface)
            .frame(height: isLive ? 120 : 52)
            .overlay {
                if isLive {
                    ProgressView().tint(Theme.secondaryText)
                } else {
                    Label("Card incomplete", systemImage: "rectangle.dashed")
                        .font(Theme.sans(13, weight: .medium))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .opacity(isLive && !reduceMotion ? (on ? 1 : 0.6) : 1)
            .animation(isLive && !reduceMotion ? .easeInOut(duration: 0.9).repeatForever() : nil, value: on)
            .onAppear { if isLive && !reduceMotion { on = true } }
            .accessibilityLabel(isLive ? "Loading card" : "Card incomplete")
    }
}
