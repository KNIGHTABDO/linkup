import SwiftUI
import UIKit

/// Live dashboard of every agent session currently running on the PC, plus recently finished runs.
struct RunningNowView: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    private var runningSessions: [SessionInfo] {
        store.sessions.filter { $0.isRunning }
    }

    private var recentlyFinishedSessions: [SessionInfo] {
        let oneHourAgo = Date().timeIntervalSince1970 - 3600
        return store.sessions
            .filter { !$0.isRunning && $0.updated >= oneHourAgo }
            .sorted { $0.updated > $1.updated }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Running Now", onClose: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if runningSessions.isEmpty {
                        emptyRunningState
                    } else {
                        runningSection
                    }

                    if !recentlyFinishedSessions.isEmpty {
                        recentlyFinishedSection
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
        .task {
            subscribeRunningSessions()
        }
        .onChange(of: runningSessions.map(\.id)) { _, _ in
            subscribeRunningSessions()
        }
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Active (\(runningSessions.count))")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 4)

            LazyVStack(spacing: 12) {
                ForEach(runningSessions) { session in
                    RunningSessionLiveCard(session: session)
                }
            }
        }
    }

    private var emptyRunningState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.secondaryText)
                .padding(.bottom, 2)

            Text("Nothing running")
                .font(Theme.sans(17, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("Sessions running on your PC will appear here live with controls.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Theme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var recentlyFinishedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Finished")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            LazyVStack(spacing: 8) {
                ForEach(recentlyFinishedSessions) { session in
                    RecentlyFinishedRow(session: session)
                }
            }
        }
    }

    private func subscribeRunningSessions() {
        for session in runningSessions {
            store.open(session.id)
        }
    }
}

// MARK: - Live Card for a Running Session

private struct RunningSessionLiveCard: View {
    let session: SessionInfo

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let transcript = store.transcript(for: session.id)
        let turn = transcript.liveTurn

        VStack(alignment: .leading, spacing: 12) {
            // Header: AgentLogo, Title, Project & Stop Button
            HStack(alignment: .top, spacing: 12) {
                Button {
                    openSession()
                } label: {
                    HStack(spacing: 12) {
                        AgentLogo(agent: session.agent, size: 26)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.displayTitle)
                                .font(Theme.sans(16, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)

                            if let project = session.projectName {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11))
                                    Text(project)
                                        .font(Theme.sans(12))
                                }
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.interrupt(session.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Stop")
                            .font(Theme.sans(12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Stop session")
            }

            // Body: live activity line
            Button {
                openSession()
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        WorkingDots()
                        ActivityShimmerText(
                            text: turn?.activityLine ?? "Working\u{2026}",
                            font: Theme.sans(14)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Divider()
                        .overlay(Theme.hairline)

                    // Footer: Elapsed timer & steps count
                    HStack(spacing: 12) {
                        TimelineView(.periodic(from: .now, by: 1.0)) { context in
                            let started = turn?.started ?? Date(timeIntervalSince1970: session.updated)
                            let elapsed = max(0, context.date.timeIntervalSince(started))
                            HStack(spacing: 4) {
                                Image(systemName: "stopwatch")
                                    .font(.system(size: 11))
                                Text(MultiFormatters.formatTimer(seconds: elapsed))
                                    .font(Theme.mono(12))
                            }
                            .foregroundStyle(Theme.secondaryText)
                        }

                        Spacer()

                        let toolCount = turn?.parts.filter { if case .tool = $0 { return true }; return false }.count ?? 0
                        let stepCount = toolCount > 0 ? toolCount : (turn?.activity.count ?? 0)
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond")
                                .font(.system(size: 11))
                            Text("\(stepCount) \(stepCount == 1 ? "step" : "steps")")
                                .font(Theme.sans(12))
                        }
                        .foregroundStyle(Theme.secondaryText)

                        if let model = session.model {
                            Text(model)
                                .font(Theme.sans(11, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Theme.surface, in: Capsule())
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture {
            openSession()
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private func openSession() {
        ui.openSession(session.id)
        ui.isShowingRunning = false
        dismiss()
    }
}

// MARK: - Recently Finished Row

private struct RecentlyFinishedRow: View {
    let session: SessionInfo

    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            ui.openSession(session.id)
            ui.isShowingRunning = false
            dismiss()
        } label: {
            HStack(spacing: 12) {
                AgentLogo(agent: session.agent, size: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.displayTitle)
                        .font(Theme.sans(15, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let project = session.projectName {
                            Text(project)
                            Text("\u{00B7}")
                        }
                        Text(MultiFormatters.timeAgo(date: session.updatedDate))
                    }
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Formatters

enum MultiFormatters {
    static func formatTimer(seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    static func formatDuration(ms: Int?) -> String {
        guard let ms, ms > 0 else { return "0s" }
        let totalSeconds = max(1, Int(round(Double(ms) / 1000.0)))
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else {
            let mins = totalSeconds / 60
            let secs = totalSeconds % 60
            return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
        }
    }

    static func timeAgo(date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let mins = seconds / 60
            return "\(mins)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else {
            let days = seconds / 86400
            return "\(days)d ago"
        }
    }
}
