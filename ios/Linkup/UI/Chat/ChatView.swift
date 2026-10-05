import SwiftUI

/// The conversation view (or the "Hello, night owl" new-chat screen when sessionId is nil).
struct ChatView: View {
    let sessionId: String?

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var isUserScrolledUp = false

    var body: some View {
        Group {
            if let id = sessionId {
                let transcript = store.transcript(for: id)
                if transcript.items.isEmpty {
                    greetingView(sessionId: id)
                } else {
                    sessionView(id: id, transcript: transcript)
                }
            } else {
                greetingView(sessionId: nil)
            }
        }
        .task(id: sessionId) {
            isUserScrolledUp = false
            if let id = sessionId {
                store.open(id)
            }
        }
    }

    // MARK: - Active Session View

    @ViewBuilder
    private func sessionView(id: String, transcript: Transcript) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(transcript.items) { item in
                        switch item {
                        case .user(let message):
                            UserBubble(message: message)
                                .id(item.id)
                        case .assistant(let turn):
                            AssistantTurnView(turn: turn, sessionId: id)
                                .id(item.id)
                        }
                    }

                    footnoteView(sessionId: id)
                        .id("chat_footnote")

                    Color.clear
                        .frame(height: 1)
                        .id("chat_bottom")
                }
                .padding(.top, 70)
                .padding(.horizontal, Theme.margin)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let distanceFromBottom = geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height)
                return distanceFromBottom > 120
            } action: { _, scrolledUp in
                withAnimation(.snappy(duration: 0.2)) {
                    isUserScrolledUp = scrolledUp
                }
            }
            .safeAreaInset(edge: .bottom) {
                ComposerView(sessionId: id)
            }
            .overlay(alignment: .bottomTrailing) {
                if isUserScrolledUp {
                    Button {
                        withAnimation(.snappy) {
                            proxy.scrollTo("chat_bottom", anchor: .bottom)
                            isUserScrolledUp = false
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 36, height: 36)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(.trailing, Theme.margin)
                    .padding(.bottom, 12)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .onChange(of: transcript.items.count) { oldCount, newCount in
                if newCount > oldCount {
                    if case .user = transcript.items.last {
                        isUserScrolledUp = false
                        withAnimation(.snappy) {
                            proxy.scrollTo("chat_bottom", anchor: .bottom)
                        }
                    } else if !isUserScrolledUp {
                        withAnimation(.smooth(duration: 0.15)) {
                            proxy.scrollTo("chat_bottom", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: transcript.lastSeq) { _, _ in
                if transcript.isWorking && !isUserScrolledUp {
                    proxy.scrollTo("chat_bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Greeting / New Chat Screen

    private func greetingView(sessionId: String?) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                SparkView(size: 44)

                Text(greetingText)
                    .font(Theme.serif(30))
                    .foregroundStyle(Theme.text.opacity(0.9))
                    .multilineTextAlignment(.center)

                if let title = agentTitle(sessionId: sessionId) {
                    Button {
                        ui.isShowingModelPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            if let symbol = agentSymbol(sessionId: sessionId) {
                                Image(systemName: symbol)
                                    .font(Theme.sans(11, weight: .medium))
                            }
                            Text(title)
                                .font(Theme.sans(12, weight: .medium))
                        }
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.margin)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 70)
        .safeAreaInset(edge: .bottom) {
            ComposerView(sessionId: sessionId)
        }
    }

    // MARK: - Helpers

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<21:
            return "Good evening"
        default:
            return "Hello, night owl"
        }
    }

    private func agentTitle(sessionId: String?) -> String? {
        let agentId = sessionId.flatMap { store.session($0)?.agent } ?? ui.draftAgent
        return AgentKind(rawValue: agentId)?.title ?? store.agent(agentId)?.name
    }

    private func agentSymbol(sessionId: String?) -> String? {
        let agentId = sessionId.flatMap { store.session($0)?.agent } ?? ui.draftAgent
        return AgentKind(rawValue: agentId)?.symbol
    }

    private func footnoteView(sessionId: String) -> some View {
        let agentId = store.session(sessionId)?.agent ?? ui.draftAgent
        let agentName = AgentKind(rawValue: agentId)?.title ?? store.agent(agentId)?.name ?? "AI"
        return Text("\(agentName) can make mistakes.")
            .font(Theme.sans(13))
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
            .padding(.bottom, 16)
    }
}
