import SwiftUI

/// Sheet for creating a new project on the PC via `store.createProject`.
struct NewProjectSheet: View {
    var onCreated: (ProjectInfo) -> Void

    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedTemplate = "empty"
    @State private var initGit = true
    @State private var addReadme = true
    @State private var isCreating = false
    @State private var errorMessage: String?

    private struct TemplateOption: Identifiable {
        let id: String
        let title: String
        let icon: String
        let description: String
    }

    private let templates: [TemplateOption] = [
        TemplateOption(
            id: "empty",
            title: "Empty",
            icon: "doc.badge.plus",
            description: "Blank project with minimal setup"
        ),
        TemplateOption(
            id: "web",
            title: "Web",
            icon: "globe",
            description: "HTML, CSS and JavaScript workspace"
        ),
        TemplateOption(
            id: "python",
            title: "Python",
            icon: "curlybraces",
            description: "Python environment with main script"
        ),
        TemplateOption(
            id: "ios",
            title: "iOS app",
            icon: "apple.logo",
            description: "Native SwiftUI project layout"
        )
    ]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasInvalidCharacters: Bool {
        guard !name.isEmpty else { return false }
        return !name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == " " }
    }

    private var isValidName: Bool {
        !trimmedName.isEmpty && !hasInvalidCharacters
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // 1. Name input field
                    nameSection

                    // 2. Large selectable template cards
                    templateSection

                    // 3. Git & README toggles
                    togglesSection

                    // 4. Inline error notice if creation failed
                    if let errorMessage {
                        inlineErrorBox(errorMessage)
                    }

                    // 5. Create button (glassProminent)
                    createButton
                }
                .padding(20)
            }
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surface)
    }

    // MARK: - Subviews

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project name")
                .font(Theme.sans(14, weight: .medium))
                .foregroundStyle(Theme.secondaryText)

            TextField("my-project", text: $name)
                .font(Theme.sans(17))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(hasInvalidCharacters ? Theme.danger : Theme.hairline, lineWidth: 1)
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if hasInvalidCharacters {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Only letters, numbers, hyphens, underscores and spaces are allowed.")
                        .font(Theme.sans(12))
                }
                .foregroundStyle(Theme.danger)
            }
        }
    }

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Template")
                .font(Theme.sans(14, weight: .medium))
                .foregroundStyle(Theme.secondaryText)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(templates) { item in
                    templateCard(item)
                }
            }
        }
    }

    private func templateCard(_ item: TemplateOption) -> some View {
        let isSelected = selectedTemplate == item.id

        return Button {
            selectedTemplate = item.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: item.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.text)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.accent)
                    }
                }

                Text(item.title)
                    .font(Theme.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Text(item.description)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 110)
            .background(Theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Theme.accent : Theme.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title) template, \(item.description)")
    }

    private var togglesSection: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $initGit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Initialize git")
                        .font(Theme.sans(16))
                        .foregroundStyle(Theme.text)
                    Text("Creates a new repository with an initial commit")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.accent)

            Divider()
                .overlay(Theme.hairline)

            Toggle(isOn: $addReadme) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add README")
                        .font(Theme.sans(16))
                        .foregroundStyle(Theme.text)
                    Text("Includes a standard README.md file")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.accent)
        }
        .padding(14)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
    }

    private func inlineErrorBox(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.danger)

            Text(error)
                .font(Theme.sans(14))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.danger.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.danger.opacity(0.3), lineWidth: 1))
    }

    private var createButton: some View {
        Button {
            performCreate()
        } label: {
            HStack(spacing: 8) {
                if isCreating {
                    ProgressView()
                        .tint(.white)
                }
                Text("Create project")
                    .font(Theme.sans(17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.glassProminent)
        .disabled(!isValidName || isCreating)
        .padding(.top, 4)
    }

    private func performCreate() {
        guard isValidName, !isCreating else { return }
        isCreating = true
        errorMessage = nil

        Task {
            do {
                let templateArg = selectedTemplate == "empty" ? nil : selectedTemplate
                let project = try await store.createProject(
                    name: trimmedName,
                    git: initGit,
                    readme: addReadme,
                    template: templateArg
                )
                isCreating = false
                onCreated(project)
                dismiss()
            } catch {
                isCreating = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
