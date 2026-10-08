import SwiftUI
import UIKit

/// Configuration sheet to prompt multiple agents simultaneously and compare their outputs.
struct CompareSheet: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var selectedAgents: Set<String> = ["claude", "agy", "hermes"]
    @State private var selectedCwd: String?
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var createdSessionIds: [String] = []
    @State private var isNavigatingToCompare = false

    private let availableAgents: [(id: String, name: String)] = [
        ("claude", "Claude Code"),
        ("agy", "Antigravity"),
        ("hermes", "Hermes")
    ]

    private var selectedProjectName: String {
        if let cwd = selectedCwd, !cwd.isEmpty {
            return store.projects.first(where: { $0.path == cwd })?.name ?? URL(fileURLWithPath: cwd).lastPathComponent
        }
        return "Default directory (none)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetHeader(title: "Compare Agents", onClose: { dismiss() })

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        agentsSection
                        promptSection
                        projectSection

                        if let errorMessage {
                            Text(errorMessage)
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.danger)
                                .padding(.horizontal, 4)
                        }

                        runButton
                    }
                    .padding(.horizontal, Theme.margin)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Theme.surface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isNavigatingToCompare) {
                CompareView(sessionIds: createdSessionIds)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
        .task {
            if selectedCwd == nil {
                selectedCwd = ui.draftProject
            }
            await store.loadProjects()
        }
    }

    // MARK: - Agents Section

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agents")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(availableAgents, id: \.id) { agent in
                    let isSelected = selectedAgents.contains(agent.id)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if isSelected {
                            if selectedAgents.count > 1 {
                                selectedAgents.remove(agent.id)
                            }
                        } else {
                            selectedAgents.insert(agent.id)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            AgentLogo(agent: agent.id, size: 24)

                            Text(agent.name)
                                .font(Theme.sans(13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(
                            isSelected ? Theme.accent.opacity(0.18) : Theme.elevated,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? Theme.accent : Theme.hairline, lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prompt")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Enter a prompt to run across selected agents…")
                        .font(Theme.sans(16))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $prompt)
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 120, maxHeight: 180)
            }
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
        }
    }

    // MARK: - Project Picker Section

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Project (Optional)")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            Menu {
                Button {
                    selectedCwd = nil
                } label: {
                    HStack {
                        Text("Default directory (none)")
                        if selectedCwd == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                ForEach(store.projects) { project in
                    Button {
                        selectedCwd = project.path
                    } label: {
                        HStack {
                            Text(project.name)
                            if selectedCwd == project.path {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.accent)

                    Text(selectedProjectName)
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Run Button

    private var runButton: some View {
        Button {
            runComparison()
        } label: {
            HStack(spacing: 8) {
                if isRunning {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Run on all (\(selectedAgents.count))")
                        .font(Theme.sans(16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAgents.isEmpty || isRunning)
        .padding(.top, 6)
    }

    private func runComparison() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !selectedAgents.isEmpty else { return }

        isRunning = true
        errorMessage = nil

        Task {
            do {
                let orderedAgents = availableAgents.map(\.id).filter { selectedAgents.contains($0) }
                let sessions = try await store.compare(trimmedPrompt, agents: orderedAgents, cwd: selectedCwd)
                createdSessionIds = sessions.map(\.id)
                isRunning = false
                isNavigatingToCompare = true
            } catch {
                isRunning = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
