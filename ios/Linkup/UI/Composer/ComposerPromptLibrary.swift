import SwiftUI

/// A user-saved prompt snippet stored in UserDefaults.
struct SavedPrompt: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var text: String

    init(id: String = UUID().uuidString, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

/// Storage helper for user's prompt library.
enum PromptLibraryStore {
    static let userDefaultsKey = "linkup_saved_prompts"
    static let didChange = Notification.Name("LinkupPromptLibraryChanged")

    static func load() -> [SavedPrompt] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let list = try? JSONDecoder().decode([SavedPrompt].self, from: data) else {
            return defaultPrompts
        }
        return list
    }

    static func save(_ items: [SavedPrompt]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static let defaultPrompts: [SavedPrompt] = [
        SavedPrompt(
            title: "Review changes",
            text: "Review the recent changes in the repository, checking for edge cases, performance, and correctness."
        ),
        SavedPrompt(
            title: "Explain code",
            text: "Explain how this architecture and flow work step by step."
        ),
        SavedPrompt(
            title: "Write tests",
            text: "Write comprehensive unit tests covering happy paths, error handling, and boundary conditions."
        ),
        SavedPrompt(
            title: "Fix errors",
            text: "Diagnose and fix the errors reported in the recent run, with minimal diff."
        )
    ]
}

/// Seed for the prompt editor sheet (`.sheet(item:)`).
struct PromptEditorSeed: Identifiable {
    let id = UUID()
    var text: String
}

/// Horizontally scrolling chips shown while the composer is empty: the user's saved prompts and a "+" chip.
/// Tap inserts the prompt, the context menu deletes it.
struct ComposerPromptLibraryView: View {
    let onSelect: (String) -> Void
    let onAdd: () -> Void

    @State private var prompts: [SavedPrompt] = PromptLibraryStore.load()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    addChip
                    ForEach(prompts) { prompt in
                        promptChip(prompt)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: PromptLibraryStore.didChange)) { _ in
            prompts = PromptLibraryStore.load()
        }
    }

    private var addChip: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onAdd()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Capsule())
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("New saved prompt")
    }

    private func promptChip(_ prompt: SavedPrompt) -> some View {
        Button {
            onSelect(prompt.text)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(prompt.title)
                .font(Theme.sans(14, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .contentShape(Capsule())
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .contextMenu {
            Button(role: .destructive) {
                delete(prompt)
            } label: {
                Label("Delete prompt", systemImage: "trash")
            }
        }
        .accessibilityHint("Inserts this prompt into the message")
    }

    private func delete(_ prompt: SavedPrompt) {
        var list = prompts
        list.removeAll { $0.id == prompt.id }
        prompts = list
        PromptLibraryStore.save(list)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// Sheet to save a reusable prompt: both fields are required, Save stays disabled until they are filled.
struct PromptEditorSheet: View {
    let seedText: String
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @FocusState private var focus: Field?
    private enum Field { case title, body }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Save prompt")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title")
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        TextField("Short name", text: $title)
                            .focused($focus, equals: .title)
                            .submitLabel(.next)
                            .onSubmit { focus = .body }
                            .padding(12)
                            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prompt")
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        TextField("What should it say?", text: $text, axis: .vertical)
                            .lineLimit(4...10)
                            .focused($focus, equals: .body)
                            .environment(\.layoutDirection, text.dominantLayoutDirection)
                            .padding(12)
                            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        save()
                    } label: {
                        Text("Save")
                            .font(Theme.sans(16, weight: .semibold))
                            .foregroundStyle(canSave ? Color.black : Theme.tertiaryText)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(canSave ? Color.white : Theme.elevated, in: Capsule())
                    }
                    .disabled(!canSave)
                }
                .font(Theme.sans(16))
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                .padding(16)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surface)
        .onAppear {
            text = seedText
            focus = .title
        }
    }

    private func save() {
        guard canSave else { return }
        var list = PromptLibraryStore.load()
        list.insert(SavedPrompt(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                text: text.trimmingCharacters(in: .whitespacesAndNewlines)), at: 0)
        PromptLibraryStore.save(list)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
