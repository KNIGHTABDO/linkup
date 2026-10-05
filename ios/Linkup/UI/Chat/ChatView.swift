import SwiftUI

/// The conversation view (or the "Hello, night owl" new-chat screen when sessionId is nil).
struct ChatView: View {
    let sessionId: String?

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var isUserScrolledUp = false
    @State private var lastAutoScrollTime: Date = .distantPast
    @State private var autoScrollTask: Task<Void, Never>?

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
            autoScrollTask?.cancel()
            autoScrollTask = nil
            if let id = sessionId {
                store.open(id)
            }
        }
    }

    // MARK: - Active Session View

    @ViewBuilder
    private func sessionView(id: String, transcript: Transcript) -> some View {
        let pinned = pinnedTurns(for: id, transcript: transcript)
        let isChatMode = store.session(id)?.mode == "chat"

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(transcript.items) { item in
                        switch item {
                        case .user(let message):
                            UserBubble(message: message, sessionId: id)
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
                .padding(.top, pinned.isEmpty ? 70 : 12)
                .padding(.horizontal, Theme.margin)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.chatTextSize, isChatMode ? 18 : 17)
            .safeAreaInset(edge: .top) {
                if !pinned.isEmpty {
                    pinnedStrip(turns: pinned, proxy: proxy, sessionId: id)
                        .padding(.top, 60)
                        .background {
                            LinearGradient(
                                colors: [Theme.background, Theme.background.opacity(0.92), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .ignoresSafeArea(edges: .top)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let distanceFromBottom = geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height)
                // Relax threshold during active streaming so rapid content expansion does not falsely flip isUserScrolledUp
                let threshold: CGFloat = transcript.isWorking ? 180 : 120
                return distanceFromBottom > threshold
            } action: { _, scrolledUp in
                if isUserScrolledUp != scrolledUp {
                    withAnimation(.snappy(duration: 0.2)) {
                        isUserScrolledUp = scrolledUp
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ComposerView(sessionId: id)
            }
            .overlay(alignment: .bottomTrailing) {
                if isUserScrolledUp {
                    Button {
                        isUserScrolledUp = false
                        withAnimation(.snappy) {
                            proxy.scrollTo("chat_bottom", anchor: .bottom)
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
                scrollGluedToBottom(proxy: proxy, transcript: transcript)
            }
            .onChange(of: transcript.isWorking) { wasWorking, isWorking in
                if wasWorking && !isWorking && !isUserScrolledUp {
                    // Turn just completed, ensure grounded smoothly at bottom
                    withAnimation(.smooth(duration: 0.2)) {
                        proxy.scrollTo("chat_bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Auto-Scroll Smoothing

    private func scrollGluedToBottom(proxy: ScrollViewProxy, transcript: Transcript) {
        guard transcript.isWorking, !isUserScrolledUp else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastAutoScrollTime)

        // Throttle auto-scroll to at most every 75 ms during high-frequency token arrivals
        // to prevent competing layout passes and eliminate jitter
        if elapsed >= 0.075 {
            autoScrollTask?.cancel()
            autoScrollTask = nil
            lastAutoScrollTime = now
            proxy.scrollTo("chat_bottom", anchor: .bottom)
        } else if autoScrollTask == nil {
            let delay = max(0.02, 0.075 - elapsed)
            autoScrollTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if !Task.isCancelled && transcript.isWorking && !isUserScrolledUp {
                    lastAutoScrollTime = Date()
                    proxy.scrollTo("chat_bottom", anchor: .bottom)
                    autoScrollTask = nil
                }
            }
        }
    }

    // MARK: - Pinned Turns

    private func pinnedTurns(for sid: String, transcript: Transcript) -> [AssistantTurn] {
        let pinnedIds = PinnedStore.shared.pinnedIds(for: sid)
        guard !pinnedIds.isEmpty else { return [] }
        return transcript.items.compactMap { item in
            if case .assistant(let turn) = item, pinnedIds.contains(turn.id) {
                return turn
            }
            return nil
        }
    }

    private func pinnedStrip(turns: [AssistantTurn], proxy: ScrollViewProxy, sessionId: String) -> some View {
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
                    let snippet = pinnedTurnSnippet(turn)
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.snappy(duration: 0.35)) {
                                proxy.scrollTo(turn.id, anchor: .top)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(snippet)
                                .font(Theme.sans(12, weight: .medium))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.snappy) {
                                PinnedStore.shared.unpin(turnId: turn.id, in: sessionId)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.tertiaryText)
                                .frame(width: 14, height: 14)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Unpin message")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                }
            }
            .padding(.horizontal, Theme.margin)
        }
        .padding(.vertical, 6)
    }

    private func pinnedTurnSnippet(_ turn: AssistantTurn) -> String {
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
        return turn.model ?? "Answer"
    }

    // MARK: - Greeting / New Chat Screen

    private func greetingView(sessionId: String?) -> some View {
        let isChatMode = sessionId.flatMap { store.session($0) }?.mode == "chat"

        return VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                SparkView(size: 44)

                Text(greetingText)
                    .font(Theme.serif(30))
                    .foregroundStyle(Theme.text.opacity(0.9))
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
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

                    if isChatMode {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Chat")
                                .font(Theme.sans(11, weight: .semibold))
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
