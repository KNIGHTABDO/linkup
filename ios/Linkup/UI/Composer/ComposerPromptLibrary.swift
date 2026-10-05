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

/// Horizontally scrolling glass chips above the text field when it's empty and focused:
/// the user's saved prompts, "+" chip to save current text as a prompt, long-press to delete,
/// tap inserts the text.
struct ComposerPromptLibraryView: View {
    let currentText: String
    let onSelect: (String) -> Void

    @State private var prompts: [SavedPrompt] = []
    @State private var isSaveAlertPresented = false
    @State private var newPromptTitle = ""
    @State private var promptToDelete: SavedPrompt? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                plusChip

                ForEach(prompts) { prompt in
                    promptChip(prompt)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .onAppear {
            prompts = PromptLibraryStore.load()
        }
        .alert("Save Prompt", isPresented: $isSaveAlertPresented) {
            TextField("Prompt title", text: $newPromptTitle)
            Button("Save") {
                savePrompt()
            }
            Button("Cancel", role: .cancel) {
                newPromptTitle = ""
            }
        } message: {
            Text(currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "Enter a title for this prompt template."
                 : "Enter a title for the current composer text.")
        }
        .confirmationDialog(
            "Delete Prompt?",
            isPresented: Binding(
                get: { promptToDelete != nil },
                set: { if !$0 { promptToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let p = promptToDelete {
                Button("Delete '\(p.title)'", role: .destructive) {
                    deletePrompt(p)
                }
            }
            Button("Cancel", role: .cancel) {
                promptToDelete = nil
            }
        }
    }

    private var plusChip: some View {
        Button {
            newPromptTitle = ""
            isSaveAlertPresented = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Save as prompt")
                        .font(Theme.sans(13, weight: .medium))
                }
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .frame(height: 32)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func promptChip(_ prompt: SavedPrompt) -> some View {
        Button {
            onSelect(prompt.text)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(prompt.title)
                .font(Theme.sans(13, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(height: 32)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .contextMenu {
            Button(role: .destructive) {
                deletePrompt(prompt)
            } label: {
                Label("Delete Prompt", systemImage: "trash")
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                promptToDelete = prompt
            }
        )
    }

    private func savePrompt() {
        let title = newPromptTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let textToSave = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = textToSave.isEmpty ? title : textToSave

        var list = prompts
        list.insert(SavedPrompt(title: title, text: finalContent), at: 0)
        prompts = list
        PromptLibraryStore.save(list)
        newPromptTitle = ""
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func deletePrompt(_ prompt: SavedPrompt) {
        prompts.removeAll { $0.id == prompt.id }
        PromptLibraryStore.save(prompts)
        promptToDelete = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
