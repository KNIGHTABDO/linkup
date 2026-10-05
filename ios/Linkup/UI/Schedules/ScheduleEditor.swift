import SwiftUI

/// Schedule editor sheet for creating or editing recurring agent prompt schedules.
struct ScheduleEditor: View {
    let schedule: ScheduleInfo?
    var onSaved: ((ScheduleInfo) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var title: String = ""
    @State private var selectedAgent: String = "claude"
    @State private var selectedModel: String? = nil
    @State private var selectedProject: String? = nil
    @State private var prompt: String = ""
    @State private var selectedTime: Date = Date()
    @State private var selectedDays: Set<Int> = []
    @State private var enabled: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    private let daysConfig: [(id: Int, chip: String, name: String)] = [
        (1, "M", "Monday"),
        (2, "T", "Tuesday"),
        (3, "W", "Wednesday"),
        (4, "T", "Thursday"),
        (5, "F", "Friday"),
        (6, "S", "Saturday"),
        (7, "S", "Sunday")
    ]

    init(schedule: ScheduleInfo? = nil, onSaved: ((ScheduleInfo) -> Void)? = nil) {
        self.schedule = schedule
        self.onSaved = onSaved

        let initialTime = ScheduleFormatter.dateFromTime(schedule?.time ?? "08:00")
        _selectedTime = State(initialValue: initialTime)

        if let s = schedule {
            _title = State(initialValue: s.title)
            _selectedAgent = State(initialValue: s.agent)
            _selectedModel = State(initialValue: s.model)
            _selectedProject = State(initialValue: s.cwd)
            _prompt = State(initialValue: s.prompt)
            _selectedDays = State(initialValue: Set(s.days))
            _enabled = State(initialValue: s.enabled)
        }
    }

    private var isNew: Bool {
        schedule == nil || schedule?.id.isEmpty == true
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }

                    titleSection
                    agentSection
                    modelSection
                    projectSection
                    promptSection
                    timeSection
                    daysSection
                    enabledSection

                    saveButtonSection
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surface)
        .task {
            await store.loadProjects()
            if schedule == nil && title.isEmpty {
                applyDefaultsFromUI()
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 32, height: 32)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Dismiss")

            Spacer()

            Text(isNew ? "New Schedule" : "Edit Schedule")
                .font(Theme.sans(17, weight: .semibold))
                .foregroundStyle(Theme.text)

            Spacer()

            Button {
                save()
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accent)
                        .frame(width: 32, height: 32)
                } else {
                    Text("Save")
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.accent : Theme.tertiaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }
            .disabled(!canSave || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.danger)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.danger.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Form Sections

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TITLE")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 4)

            TextField("Title (e.g. CI Morning Check)", text: $title)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AGENT")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 4)

            GlassEffectContainer {
                HStack(spacing: 6) {
                    ForEach(AgentKind.allCases, id: \.self) { kind in
                        let isSelected = selectedAgent == kind.rawValue

                        Button {
                            selectedAgent = kind.rawValue
                            if let defaultModel = store.agent(kind.rawValue)?.defaultModel {
                                selectedModel = defaultModel
                            } else {
                                selectedModel = store.agent(kind.rawValue)?.models?.first?.id
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 6) {
                                AgentLogo(agent: kind.rawValue, size: 18)
                                Text(kind.title)
                                    .font(Theme.sans(14, weight: isSelected ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 10).fill(Theme.elevated)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MODEL")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 4)

            let models = store.agent(selectedAgent)?.models ?? []

            Menu {
                Button {
                    selectedModel = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack {
                        Text("Default model")
                        if selectedModel == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                ForEach(models) { model in
                    Button {
                        selectedModel = model.id
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Text(model.name)
                            if selectedModel == model.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "cpu")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)

                    Text(selectedModelDisplayName)
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }

    private var selectedModelDisplayName: String {
        if let id = selectedModel,
           let model = store.agent(selectedAgent)?.model(id) {
            return model.name
        }
        if let def = store.agent(selectedAgent)?.defaultModel,
           let model = store.agent(selectedAgent)?.model(def) {
            return "Default (\(model.name))"
        }
        return "Default model"
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROJECT (OPTIONAL)")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 4)

            Menu {
                Button {
                    selectedProject = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack {
                        Text("Default directory (none)")
                        if selectedProject == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                ForEach(store.projects) { proj in
                    Button {
                        selectedProject = proj.path
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Text(proj.name)
                            if selectedProject == proj.path {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)

                    Text(selectedProjectDisplayName)
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }

    private var selectedProjectDisplayName: String {
        guard let path = selectedProject else { return "Default directory (none)" }
        if let proj = store.projects.first(where: { $0.path == path }) {
            return proj.name
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROMPT")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 4)

            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Enter prompt instructions to run on schedule…")
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $prompt)
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 120)
            }
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TIME")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 4)

            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)

                Text("Run at")
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.text)

                Spacer()

                DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DAYS")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 4)

            HStack(spacing: 0) {
                ForEach(daysConfig, id: \.id) { item in
                    let isSelected = selectedDays.contains(item.id)

                    Button {
                        if isSelected {
                            selectedDays.remove(item.id)
                        } else {
                            selectedDays.insert(item.id)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isSelected ? Theme.accent : Theme.elevated)
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.clear : Theme.hairline, lineWidth: 1)
                                )

                            Text(item.chip)
                                .font(Theme.sans(14, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? Color.white : Theme.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(item.name), \(isSelected ? "selected" : "not selected")")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))

            HStack {
                Image(systemName: "repeat")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiaryText)

                Text(daysSummaryText)
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.secondaryText)

                Spacer()

                if !selectedDays.isEmpty {
                    Button("Every day") {
                        selectedDays.removeAll()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var daysSummaryText: String {
        if selectedDays.isEmpty {
            return "Repeats every day (none selected)"
        }
        let timeString = ScheduleFormatter.timeFromDate(selectedTime)
        return ScheduleFormatter.cadence(time: timeString, days: Array(selectedDays).sorted())
    }

    private var enabledSection: some View {
        Toggle(isOn: $enabled) {
            HStack(spacing: 10) {
                Image(systemName: enabled ? "checkmark.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(enabled ? Theme.success : Theme.tertiaryText)

                Text("Enabled")
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.text)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
    }

    private var saveButtonSection: some View {
        Button {
            save()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(isNew ? "Create Schedule" : "Save Changes")
                    .font(Theme.sans(16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(canSave ? Theme.accent : Theme.elevated, in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canSave || isSaving)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func applyDefaultsFromUI() {
        selectedAgent = ui.draftAgent
        if let def = store.agent(ui.draftAgent)?.defaultModel {
            selectedModel = def
        } else {
            selectedModel = store.agent(ui.draftAgent)?.models?.first?.id
        }
        selectedProject = ui.draftProject
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanPrompt.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        let timeString = ScheduleFormatter.timeFromDate(selectedTime)
        let sortedDays = Array(selectedDays).sorted()

        // For new schedules, bridge expects id = ""
        let targetId = (schedule?.id.isEmpty == false) ? (schedule?.id ?? "") : ""

        let scheduleToSave = ScheduleInfo(
            id: targetId,
            title: cleanTitle,
            agent: selectedAgent,
            model: selectedModel?.isEmpty == true ? nil : selectedModel,
            cwd: selectedProject?.isEmpty == true ? nil : selectedProject,
            prompt: cleanPrompt,
            time: timeString,
            days: sortedDays,
            enabled: enabled,
            lastRun: schedule?.lastRun,
            nextRun: schedule?.nextRun,
            lastSessionId: schedule?.lastSessionId
        )

        Task {
            do {
                let saved = try await store.saveSchedule(scheduleToSave)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSaved?(saved)
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
                ui.toast = "Failed to save schedule: \(error.localizedDescription)"
            }
        }
    }
}
