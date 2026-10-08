import SwiftUI
import UIKit

/// The conversation screen: top bar and composer are system safe-area bars (real scroll-edge blur and insets), the
/// content between them is the transcript, a loading state or the new-chat greeting. There is exactly one
/// ComposerView and it survives chat switches (drafts, keyboard, dictation stay).
struct ChatView: View {
    let sessionId: String?
    var sidebarLabel = "Open sidebar"
    var onSidebar: () -> Void = {}

    @Environment(SessionStore.self) private var store

    @State private var isNearBottom = true
    @State private var bottomTick = 0
    @State private var jump: ChatScrollJump?

    var body: some View {
        ChatBody(
            sessionId: sessionId,
            isNearBottom: $isNearBottom,
            bottomTick: bottomTick,
            jump: jump
        )
        .id(sessionId ?? "new")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaBar(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                ChatTopBar(sessionId: sessionId, sidebarLabel: sidebarLabel, onSidebar: onSidebar)
                if let sessionId {
                    ChatPinnedStrip(sessionId: sessionId) { turnId in
                        jump = ChatScrollJump(id: turnId, nonce: (jump?.nonce ?? 0) + 1)
                    }
                }
            }
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if !isNearBottom {
                    scrollToBottomButton
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                ComposerView(sessionId: sessionId)
                    .frame(maxWidth: Theme.readableWidth)
                    .frame(maxWidth: .infinity)
            }
            .animation(.snappy(duration: 0.2), value: isNearBottom)
        }
        .task(id: sessionId) {
            if let sessionId { store.open(sessionId) }
        }
        .onChange(of: sessionId) { old, _ in
            isNearBottom = true
            jump = nil
            if let old { store.close(old) }
        }
    }

    private var scrollToBottomButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isNearBottom = true
            bottomTick += 1
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Scroll to latest message")
    }
}

/// Asks the transcript to scroll to a turn (pinned strip); `nonce` lets the same turn be requested twice.
struct ChatScrollJump: Equatable {
    let id: String
    let nonce: Int
}

// MARK: - Body switch (loading / greeting / transcript)

private struct ChatBody: View {
    let sessionId: String?
    @Binding var isNearBottom: Bool
    let bottomTick: Int
    let jump: ChatScrollJump?

    @Environment(SessionStore.self) private var store
    @Environment(LinkupClient.self) private var client

    var body: some View {
        if let id = sessionId {
            let transcript = store.transcript(for: id)
            if !transcript.items.isEmpty {
                ChatScroll(
                    sessionId: id,
                    transcript: transcript,
                    isNearBottom: $isNearBottom,
                    bottomTick: bottomTick,
                    jump: jump
                )
            } else if transcript.isLoading || awaitingEvents(id) {
                ChatLoadingView()
            } else {
                ChatGreeting(sessionId: id)
            }
        } else {
            ChatGreeting(sessionId: nil)
        }
    }

    /// The session has events but none arrived yet (cache still empty, bridge about to replay): never flash the greeting.
    private func awaitingEvents(_ id: String) -> Bool {
        guard (store.session(id)?.lastSeq ?? 0) > 0 else { return false }
        return client.state == .connected || client.state == .connecting
    }
}

private struct ChatLoadingView: View {
    var body: some View {
        ProgressView()
            .controlSize(.regular)
            .tint(Theme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading conversation")
    }
}

// MARK: - Transcript scroll

/// Plain reference so scroll bookkeeping never re-renders the view.
private final class ChatScrollTracker {
    var userDriven = false
}

private struct ChatScroll: View {
    let sessionId: String
    let transcript: Transcript
    @Binding var isNearBottom: Bool
    let bottomTick: Int
    let jump: ChatScrollJump?

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var tracker = ChatScrollTracker()

    var body: some View {
        ScrollView {
            ChatRowsHost(sessionId: sessionId, transcript: transcript)
        }
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .onScrollPhaseChange { _, phase in
            tracker.userDriven = phase == .tracking || phase == .interacting || phase == .decelerating
        }
        // Whether the user left the bottom is decided only while they are scrolling, never from content growth.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let bottomEdge = geometry.contentSize.height + geometry.contentInsets.bottom
            let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
            return bottomEdge - visibleBottom < 48
        } action: { _, nearBottom in
            guard tracker.userDriven, isNearBottom != nearBottom else { return }
            isNearBottom = nearBottom
        }
        .background {
            ChatAutoScroller(transcript: transcript, isNearBottom: $isNearBottom) { animated in
                scrollToBottom(animated: animated)
            }
        }
        .onChange(of: bottomTick) { _, _ in scrollToBottom(animated: true) }
        .onChange(of: jump) { _, request in
            guard let request else { return }
            isNearBottom = false
            withAnimation(.snappy(duration: 0.35)) {
                position.scrollTo(id: request.id, anchor: .top)
            }
        }
        .task {
            // Rows are measured lazily: settle once on the real bottom after the first layout pass.
            try? await Task.sleep(for: .milliseconds(80))
            scrollToBottom(animated: false)
        }
        .onDisappear { isNearBottom = true }
    }

    private func scrollToBottom(animated: Bool) {
        if animated {
            withAnimation(.snappy(duration: 0.3)) { position.scrollTo(edge: .bottom) }
        } else {
            position.scrollTo(edge: .bottom)
        }
    }
}

/// The only reader of `transcript.lastSeq`: every streamed event re-renders this empty view, not the chat.
private struct ChatAutoScroller: View {
    let transcript: Transcript
    @Binding var isNearBottom: Bool
    let scroll: (Bool) -> Void

    @State private var pending: Task<Void, Never>?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: transcript.lastSeq) { _, _ in follow() }
            .onChange(of: transcript.items.count) { old, new in
                // The user just sent something: always show it.
                if new > old, case .user = transcript.items.last {
                    isNearBottom = true
                    scroll(true)
                }
            }
    }

    /// Coalesces bursts of tokens into one scroll per ~50 ms.
    private func follow() {
        guard isNearBottom, pending == nil else { return }
        pending = Task { @MainActor in
            defer { pending = nil }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, isNearBottom else { return }
            scroll(false)
        }
    }
}

/// Reads the chat mode here so a session push never re-renders the rows (their inputs stay equal).
private struct ChatRowsHost: View {
    let sessionId: String
    let transcript: Transcript

    @Environment(SessionStore.self) private var store

    var body: some View {
        ChatRows(sessionId: sessionId, transcript: transcript)
            .environment(\.chatTextSize, store.session(sessionId)?.mode == "chat" ? 18 : 17)
    }
}

private struct ChatRows: View {
    let sessionId: String
    let transcript: Transcript

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(transcript.items) { item in
                switch item {
                case .user(let message):
                    UserBubble(message: message, sessionId: sessionId)
                        .id(item.id)
                case .assistant(let turn):
                    AssistantTurnView(turn: turn, sessionId: sessionId)
                        .id(item.id)
                }
            }

            ChatFootnote(sessionId: sessionId)
        }
        .scrollTargetLayout()
        .padding(.top, 12)
        .padding(.horizontal, Theme.margin)
        .frame(maxWidth: Theme.readableWidth)
        .frame(maxWidth: .infinity)
    }
}

private struct ChatFootnote: View {
    let sessionId: String

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        let agentId = store.session(sessionId)?.agent ?? ui.draftAgent
        let agentName = AgentKind(rawValue: agentId)?.title ?? store.agent(agentId)?.name ?? "AI"
        Text("\(agentName) can make mistakes.")
            .font(Theme.sans(13))
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
            .padding(.bottom, 16)
    }
}

// MARK: - Pinned turns

private struct ChatPinnedStrip: View {
    let sessionId: String
    let onJump: (String) -> Void

    @Environment(SessionStore.self) private var store

    private var pinnedTurns: [AssistantTurn] {
        let pinnedIds = PinnedStore.shared.pinnedIds(for: sessionId)
        guard !pinnedIds.isEmpty else { return [] }
        return store.transcript(for: sessionId).items.compactMap { item in
            if case .assistant(let turn) = item, pinnedIds.contains(turn.id) { return turn }
            return nil
        }
    }

    var body: some View {
        let turns = pinnedTurns
        if !turns.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text("Pinned")
                            .font(Theme.sans(12, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.trailing, 2)

                    ForEach(turns) { turn in
                        pinnedChip(turn)
                    }
                }
                .padding(.horizontal, Theme.margin)
            }
            .padding(.bottom, 2)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func pinnedChip(_ turn: AssistantTurn) -> some View {
        HStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onJump(turn.id)
            } label: {
                Text(snippet(turn))
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Jump to pinned answer: \(snippet(turn))")

            Button {
                withAnimation(.snappy) {
                    PinnedStore.shared.unpin(turnId: turn.id, in: sessionId)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unpin message")
        }
        .background {
            Capsule()
                .fill(Theme.surface)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                .frame(height: 32)
        }
    }

    private func snippet(_ turn: AssistantTurn) -> String {
        if let firstText = turn.textBlocks.first?.text {
            let cleaned = firstText
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                let firstLine = cleaned.components(separatedBy: "\n").first ?? cleaned
                return String(firstLine.prefix(24))
            }
        }
        return "Answer"
    }
}

// MARK: - Greeting / new chat

private struct ChatGreeting: View {
    let sessionId: String?

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    private var session: SessionInfo? { sessionId.flatMap { store.session($0) } }
    private var agentId: String { session?.agent ?? ui.draftAgent }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "Welcome back"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            SparkView(size: 44)

            Text(greetingText)
                .font(Theme.serif(30))
                .foregroundStyle(Theme.text.opacity(0.9))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                if let kind = AgentKind(rawValue: agentId) {
                    Button {
                        ui.isShowingModelPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: kind.symbol)
                                .font(Theme.sans(11, weight: .medium))
                            Text(kind.title)
                                .font(Theme.sans(12, weight: .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background {
                            Capsule()
                                .fill(Theme.surface)
                                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                                .frame(height: 28)
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Agent: \(kind.title). Choose model")
                }

                if session?.mode == "chat" {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Chat")
                            .font(Theme.sans(11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Theme.accent.opacity(0.25), lineWidth: 1))
                    .accessibilityLabel("Chat mode session")
                }
            }
        }
        .padding(.horizontal, Theme.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
