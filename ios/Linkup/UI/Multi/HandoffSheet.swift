import SwiftUI
import UIKit

/// Sheet to hand off an ongoing conversation to another agent with full transcript context.
struct HandoffSheet: View {
    let sessionId: String

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAgentId = "agy"
    @State private var selectedModelId: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private struct TargetAgentItem: Identifiable {
        let id: String
        let name: String
        let strengths: String
    }

    private let targetAgents: [TargetAgentItem] = [
        TargetAgentItem(
            id: "claude",
            name: "Claude Code",
            strengths: "Best for code and long tasks"
        ),
        TargetAgentItem(
            id: "agy",
            name: "Antigravity",
            strengths: "Gemini models, image generation, browser"
        ),
        TargetAgentItem(
            id: "hermes",
            name: "Hermes",
            strengths: "Your personal agent with memory"
        )
    ]

    private var currentSession: SessionInfo? {
        store.session(sessionId)
    }

    private var targetAgentInfo: AgentInfo? {
        store.agent(selectedAgentId)
    }

    private var effectiveSelectedModelId: String? {
        selectedModelId ?? targetAgentInfo?.defaultModel ?? targetAgentInfo?.models?.first?.id
    }

    private var selectedAgentName: String {
        targetAgents.first(where: { $0.id == selectedAgentId })?.name ?? "Agent"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Hand Off", onClose: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    agentSelectionSection
                    modelPickerSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 4)
                    }

                    continueButton
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
            setupInitialSelection()
            await store.refreshCatalog(force: false)
            if selectedModelId == nil {
                selectedModelId = targetAgentInfo?.defaultModel ?? targetAgentInfo?.models?.first?.id
            }
        }
    }

    // MARK: - Agent Selection Section

    private var agentSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Target Agent")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                ForEach(targetAgents) { agent in
                    let isSelected = (selectedAgentId == agent.id)
                    let isCurrent = (currentSession?.agent == agent.id)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedAgentId = agent.id
                        if let agentInfo = store.agent(agent.id) {
                            selectedModelId = agentInfo.defaultModel ?? agentInfo.models?.first?.id
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            AgentLogo(agent: agent.id, size: 28)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(agent.name)
                                        .font(Theme.sans(16, weight: .semibold))
                                        .foregroundStyle(Theme.text)

                                    if isCurrent {
                                        Text("Current")
                                            .font(Theme.sans(11, weight: .medium))
                                            .foregroundStyle(Theme.secondaryText)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Theme.surface, in: Capsule())
                                    }
                                }

                                Text(agent.strengths)
                                    .font(Theme.sans(13))
                                    .foregroundStyle(Theme.secondaryText)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer(minLength: 8)

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            } else {
                                Circle()
                                    .stroke(Theme.hairline, lineWidth: 1.5)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .padding(14)
                        .background(
                            isSelected ? Theme.elevated : Theme.surface,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? Theme.accent : Theme.hairline, lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Model Picker Section

    private var modelPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            let models = targetAgentInfo?.models ?? []

            VStack(spacing: 0) {
                if models.isEmpty {
                    HStack {
                        Text(targetAgentInfo?.available == false ? "Agent is offline" : "Default model")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                    }
                    .padding(16)
                } else {
                    ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                        let isModelSelected = (model.id == effectiveSelectedModelId)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedModelId = model.id
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(Theme.sans(16, weight: .medium))
                                        .foregroundStyle(Theme.text)

                                    if let desc = model.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(Theme.sans(13))
                                            .foregroundStyle(Theme.secondaryText)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                if isModelSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < models.count - 1 {
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            performHandoff()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Continue with \(selectedAgentName)")
                        .font(Theme.sans(16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .disabled(isLoading)
        .padding(.top, 6)
    }

    // MARK: - Actions

    private func setupInitialSelection() {
        if let currentAgent = currentSession?.agent {
            if currentAgent == "claude" {
                selectedAgentId = "agy"
            } else if currentAgent == "agy" {
                selectedAgentId = "claude"
            } else {
                selectedAgentId = "claude"
            }
        }
    }

    private func performHandoff() {
        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }
            do {
                let newSession = try await store.handoff(
                    sessionId,
                    to: selectedAgentId,
                    model: effectiveSelectedModelId
                )
                ui.openSession(newSession.id)
                ui.handoffSessionId = nil
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
