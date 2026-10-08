import SwiftUI
import UIKit

/// Side-by-side (iPad) or paged (iPhone) comparison view for multiple agent sessions.
struct CompareView: View {
    let sessionIds: [String]

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedPageIndex = 0

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Comparison", onClose: {
                ui.isShowingCompare = false
                dismiss()
            })
            segmentedHeader

            if isPad {
                iPadColumnsLayout
            } else {
                iPhonePagedLayout
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            subscribeAllSessions()
        }
    }

    // MARK: - Top Segmented Header

    private var segmentedHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(sessionIds.enumerated()), id: \.element) { index, sid in
                    let session = store.session(sid)
                    let transcript = store.transcript(for: sid)
                    let turn = transcript.liveTurn ?? transcript.lastAssistantTurn
                    let isSelected = selectedPageIndex == index

                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            selectedPageIndex = index
                        }
                    } label: {
                        HStack(spacing: 6) {
                            AgentLogo(agent: session?.agent ?? "claude", size: 16)

                            Text(agentShortName(for: session?.agent))
                                .font(Theme.sans(13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)

                            if session?.isRunning == true || transcript.isWorking {
                                WorkingDots()
                            } else if turn != nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.success)

                                if let ms = turn?.durationMs {
                                    Text(MultiFormatters.formatDuration(ms: ms))
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? Theme.elevated : Theme.surface,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Theme.accent : Theme.hairline, lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    // MARK: - iPad Layout (Side-by-side Columns)

    private var iPadColumnsLayout: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(sessionIds, id: \.self) { sid in
                CompareColumnView(sessionId: sid)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - iPhone Layout (Paged TabView)

    private var iPhonePagedLayout: some View {
        TabView(selection: $selectedPageIndex) {
            ForEach(Array(sessionIds.enumerated()), id: \.element) { index, sid in
                CompareColumnView(sessionId: sid)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func agentShortName(for agent: String?) -> String {
        switch agent {
        case "claude": "Claude"
        case "agy": "Antigravity"
        case "hermes": "Hermes"
        default: agent?.capitalized ?? "Agent"
        }
    }

    private func subscribeAllSessions() {
        for sid in sessionIds {
            store.open(sid)
        }
    }
}

// MARK: - Column for Single Session in Comparison

private struct CompareColumnView: View {
    let sessionId: String

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let session = store.session(sessionId)
        let transcript = store.transcript(for: sessionId)
        let turn = transcript.liveTurn ?? transcript.lastAssistantTurn
        let isStreaming = turn?.isLive == true
        let responseText = turn?.textBlocks.map(\.text).joined(separator: "\n\n") ?? ""

        VStack(spacing: 0) {
            // Column Header
            HStack(spacing: 10) {
                AgentLogo(agent: session?.agent ?? "claude", size: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agentTitle(for: session?.agent))
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    if let model = session?.model {
                        Text(model)
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    ui.openSession(sessionId)
                    ui.isShowingCompare = false
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Text("Open")
                            .font(Theme.sans(13, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Open session in chat")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.elevated)

            Divider()
                .overlay(Theme.hairline)

            // Transcript Scroll Content
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Live Activity Line
                    if isStreaming {
                        HStack(spacing: 8) {
                            WorkingDots()
                            ActivityShimmerText(
                                text: turn?.activityLine ?? "Working\u{2026}",
                                font: Theme.sans(14)
                            )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else if let line = turn?.activityLine {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.success)

                            Text(line)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // Assistant Text
                    if responseText.isEmpty {
                        if isStreaming {
                            HStack(spacing: 6) {
                                Text("Thinking\u{2026}")
                                    .font(Theme.serif(16))
                                    .foregroundStyle(Theme.secondaryText)
                                    .italic()
                            }
                            .padding(.vertical, 20)
                        } else {
                            Text("No output received.")
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.vertical, 20)
                        }
                    } else {
                        RichTextView(text: responseText, isStreaming: isStreaming)
                            .font(Theme.serif(16))
                            .environment(\.cardActions, CardActions(send: { text in store.send(text, to: sessionId) }))
                    }
                }
                .padding(14)
            }

            Divider()
                .overlay(Theme.hairline)

            // Footer: Tokens & Duration
            columnFooter(session: session, turn: turn)
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private func columnFooter(session: SessionInfo?, turn: AssistantTurn?) -> some View {
        let inputTokens = turn?.usage?.input ?? session?.usage?.inputTokens ?? 0
        let outputTokens = turn?.usage?.output ?? session?.usage?.outputTokens ?? 0
        let totalTokens = inputTokens + outputTokens

        return HStack(spacing: 12) {
            if totalTokens > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "number")
                        .font(.system(size: 11))
                    Text("\(totalTokens.formatted()) tokens")
                        .font(Theme.mono(12))
                }
                .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Ready")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.tertiaryText)
            }

            Spacer()

            if let ms = turn?.durationMs {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(MultiFormatters.formatDuration(ms: ms))
                        .font(Theme.mono(12))
                }
                .foregroundStyle(Theme.secondaryText)
            } else if turn?.isLive == true {
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    let start = turn?.started ?? Date()
                    let elapsed = max(0, context.date.timeIntervalSince(start))
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 11))
                        Text(MultiFormatters.formatTimer(seconds: elapsed))
                            .font(Theme.mono(12))
                    }
                    .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }

    private func agentTitle(for agent: String?) -> String {
        switch agent {
        case "claude": "Claude Code"
        case "agy": "Antigravity"
        case "hermes": "Hermes"
        default: agent?.capitalized ?? "Agent"
        }
    }
}
