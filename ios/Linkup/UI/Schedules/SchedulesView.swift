import SwiftUI

/// Main schedules management screen: lists recurring prompt schedules, lets user run now,
/// toggle, swipe-delete, edit, or create new scheduled prompts.
struct SchedulesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var schedules: [ScheduleInfo] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var editingSchedule: ScheduleInfo? = nil
    @State private var isShowingEditor: Bool = false
    @State private var runningScheduleId: String? = nil

    private let exampleTemplates: [ScheduleExampleTemplate] = [
        ScheduleExampleTemplate(
            id: "ci-repos",
            title: "Summarize my repos\u{2019} CI every morning",
            cadenceLabel: "Every weekday at 08:00 · Claude Code",
            agent: "claude",
            prompt: "Check GitHub CI runs across my active repositories. Summarize failed workflows, recent test passes, and pending runs.",
            time: "08:00",
            days: [1, 2, 3, 4, 5]
        ),
        ScheduleExampleTemplate(
            id: "daily-briefing",
            title: "Daily news briefing with cards",
            cadenceLabel: "Every day at 09:00 · Antigravity",
            agent: "agy",
            prompt: "Generate a daily tech and AI news briefing. Format top stories, model releases, and security advisories into rich cards.",
            time: "09:00",
            days: []
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Schedules", onClose: { dismiss() }) {
                Button {
                    editingSchedule = nil
                    isShowingEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("New Schedule")
            }

            ZStack {
                Theme.surface.ignoresSafeArea()

                contentView
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
        .sheet(isPresented: $isShowingEditor) {
            ScheduleEditor(schedule: editingSchedule) { saved in
                handleSaved(saved)
            }
        }
        .task {
            await loadSchedules()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if isLoading && schedules.isEmpty {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(Theme.accent)
                Text("Loading schedules…")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if schedules.isEmpty {
            emptyStateView
        } else {
            listView
        }
    }

    // MARK: - List View

    private var listView: some View {
        List {
            if let errorMessage {
                errorRow(errorMessage)
            }

            ForEach(schedules) { schedule in
                ScheduleRowView(
                    schedule: schedule,
                    isRunning: runningScheduleId == schedule.id,
                    onToggle: { isEnabled in
                        toggleSchedule(schedule, isEnabled: isEnabled)
                    },
                    onSelect: {
                        editingSchedule = schedule
                        isShowingEditor = true
                    },
                    onRunNow: {
                        runScheduleNow(schedule)
                    },
                    onDelete: {
                        deleteSchedule(schedule)
                    }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteSchedule(schedule)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.hairline)
                .listRowInsets(EdgeInsets(top: 10, leading: Theme.margin, bottom: 10, trailing: Theme.margin))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await loadSchedules()
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let errorMessage {
                    errorRow(errorMessage)
                }

                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.accent.opacity(0.12))
                            .frame(width: 80, height: 80)

                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, 20)

                    Text("Scheduled Prompts")
                        .font(Theme.serif(24, weight: .semibold))
                        .foregroundStyle(Theme.text)

                    Text("Drive your PC\u{2019}s agents on a recurring schedule. Runs automatically in the background.")
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("SUGGESTED EXAMPLES")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 4)

                    ForEach(exampleTemplates) { example in
                        Button {
                            applyExample(example)
                        } label: {
                            HStack(spacing: 14) {
                                AgentLogo(agent: example.agent, size: 24)
                                    .frame(width: 36, height: 36)
                                    .background(Theme.surface, in: Circle())
                                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(example.title)
                                        .font(Theme.sans(15, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)

                                    Text(example.cadenceLabel)
                                        .font(Theme.sans(13))
                                        .foregroundStyle(Theme.secondaryText)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Theme.accent)
                            }
                            .padding(14)
                            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    editingSchedule = nil
                    isShowingEditor = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Create Schedule")
                            .font(Theme.sans(15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(.white)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            await loadSchedules()
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.danger)

            Text(message)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.danger)
                .lineLimit(2)

            Spacer()

            Button("Retry") {
                Task { await loadSchedules() }
            }
            .font(Theme.sans(13, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: Theme.margin, bottom: 4, trailing: Theme.margin))
    }

    // MARK: - Actions

    private func loadSchedules() async {
        isLoading = schedules.isEmpty
        do {
            schedules = try await store.schedules()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleSchedule(_ schedule: ScheduleInfo, isEnabled: Bool) {
        guard let idx = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        var updated = schedule
        updated.enabled = isEnabled
        schedules[idx] = updated
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                let saved = try await store.saveSchedule(updated)
                if let i = schedules.firstIndex(where: { $0.id == schedule.id }) {
                    schedules[i] = saved
                }
            } catch {
                if let i = schedules.firstIndex(where: { $0.id == schedule.id }) {
                    schedules[i] = schedule
                }
                ui.toast = "Failed to update schedule: \(error.localizedDescription)"
            }
        }
    }

    private func deleteSchedule(_ schedule: ScheduleInfo) {
        guard let idx = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        let removed = schedules.remove(at: idx)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                try await store.deleteSchedule(removed.id)
            } catch {
                schedules.insert(removed, at: idx)
                ui.toast = "Failed to delete schedule: \(error.localizedDescription)"
            }
        }
    }

    private func runScheduleNow(_ schedule: ScheduleInfo) {
        runningScheduleId = schedule.id
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            defer { runningScheduleId = nil }
            do {
                ui.toast = "Running \(schedule.title)…"
                if let session = try await store.runSchedule(schedule.id) {
                    ui.openSession(session.id)
                    ui.isShowingSchedules = false
                    dismiss()
                }
            } catch {
                ui.toast = "Failed to run schedule: \(error.localizedDescription)"
            }
        }
    }

    private func applyExample(_ example: ScheduleExampleTemplate) {
        editingSchedule = ScheduleInfo(
            id: "",
            title: example.title,
            agent: example.agent,
            model: nil,
            cwd: nil,
            prompt: example.prompt,
            time: example.time,
            days: example.days,
            enabled: true
        )
        isShowingEditor = true
    }

    private func handleSaved(_ saved: ScheduleInfo) {
        if let idx = schedules.firstIndex(where: { $0.id == saved.id }) {
            schedules[idx] = saved
        } else {
            schedules.insert(saved, at: 0)
        }
    }
}

// MARK: - Row View

private struct ScheduleRowView: View {
    let schedule: ScheduleInfo
    let isRunning: Bool
    let onToggle: (Bool) -> Void
    let onSelect: () -> Void
    let onRunNow: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            AgentLogo(agent: schedule.agent, size: 24)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.title.isEmpty ? "Untitled Schedule" : schedule.title)
                    .font(Theme.sans(16, weight: .medium))
                    .foregroundStyle(schedule.enabled ? Theme.text : Theme.secondaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(ScheduleFormatter.cadence(time: schedule.time, days: schedule.days))
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)

                    if schedule.enabled, let next = ScheduleFormatter.relativeNextRun(for: schedule) {
                        Text("·")
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.tertiaryText)
                        Text(next)
                            .font(Theme.sans(13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    } else if !schedule.enabled {
                        Text("·")
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.tertiaryText)
                        Text("Paused")
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }

            Spacer(minLength: 8)

            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
                    .padding(.trailing, 4)
            }

            Toggle("", isOn: Binding(
                get: { schedule.enabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .tint(Theme.accent)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button {
                onRunNow()
            } label: {
                Label("Run now", systemImage: "play.fill")
            }

            Button {
                onSelect()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Example Template Helper

private struct ScheduleExampleTemplate: Identifiable {
    let id: String
    let title: String
    let cadenceLabel: String
    let agent: String
    let prompt: String
    let time: String
    let days: [Int]
}
