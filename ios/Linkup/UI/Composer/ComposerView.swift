import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Bottom of the chat: input container with attachments, multiline text, model pill, dictation and send/stop.
/// Drafts (text, attachments, command chip, in-flight flags) live in `ComposerDraftStore`, keyed by session, so a
/// single ComposerView can stay alive (and focused) while the chat changes.
struct ComposerView: View {
    let sessionId: String?

    @Environment(SessionStore.self) private var store
    @Environment(LinkupClient.self) private var client
    @Environment(UIState.self) private var ui
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @AppStorage("draftMode") private var draftMode: String = "agent"

    @State private var dictation: ComposerDictation?
    @State private var baseDictationText = ""
    @FocusState private var isFocused: Bool

    // Slash commands
    @State private var isCommandPickerPresented = false
    @State private var commandsDismissed = false
    @State private var commandSearch = ""

    @State private var isVoiceModePresented = false

    // Pickers
    @State private var isPhotosPickerPresented = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var isFileImporterPresented = false

    @State private var promptEditorSeed: PromptEditorSeed?

    private var draft: ComposerDraft { ComposerDraftStore.shared.draft(for: sessionId) }

    private var isWorking: Bool {
        guard let sid = sessionId else { return false }
        return store.transcript(for: sid).isWorking
    }

    private var textBinding: Binding<String> {
        let d = draft
        return Binding(get: { d.text }, set: { d.text = $0 })
    }

    private var isListening: Bool { dictation?.isListening ?? false }
    private var isCompact: Bool { verticalSizeClass == .compact }

    private var currentAgentId: String {
        if let sid = sessionId, let s = store.session(sid) { return s.agent }
        return ui.draftAgent
    }

    private var agentName: String {
        let agentId = currentAgentId
        if let name = store.agent(agentId)?.name, !name.isEmpty { return name }
        return AgentKind(rawValue: agentId)?.title ?? "Claude Code"
    }

    private var commands: [CommandInfo] { store.agent(currentAgentId)?.commands ?? [] }

    private var placeholder: String {
        if draft.selectedCommand != nil { return "Add arguments (optional)\u{2026}" }
        if sessionId == nil {
            return draftMode == "chat" ? "Ask anything \u{2014} places, weather, recipes\u{2026}" : "Chat with \(agentName)"
        }
        return "Reply to \(agentName)"
    }

    private var modelPillText: (name: String, effort: String?) {
        let agentId = currentAgentId
        let rawModelId: String?
        let effort: String?
        if let sid = sessionId, let s = store.session(sid) {
            rawModelId = s.model
            effort = s.effort
        } else {
            rawModelId = ui.draftModel
            effort = ui.draftEffort
        }
        let agent = store.agent(agentId)
        let effectiveModelId = rawModelId ?? agent?.defaultModel
        let model = effectiveModelId.flatMap { agent?.model($0) }
        // "Default (recommended)" reads better as the model it points to ("Opus 5.5", from its description).
        var friendly: String?
        if model?.id == "default",
           let first = model?.description?.components(separatedBy: "\u{00B7}").first?
            .trimmingCharacters(in: .whitespaces), !first.isEmpty, first.count <= 24 {
            friendly = first
        }
        let displayName = friendly ?? model?.name ?? effectiveModelId ?? "Model"
        // Effort only where the model actually supports it.
        var effortDisplay: String?
        if let e = effort, !e.isEmpty, let efforts = model?.efforts, !efforts.isEmpty,
           efforts.contains(where: { $0.lowercased() == e.lowercased() }) {
            effortDisplay = e.capitalized
        }
        return (displayName, effortDisplay)
    }

    private var ringUtilization: Double? {
        guard currentAgentId == "claude" else { return nil }
        return store.usage?.claudePlan?.fiveHour?.utilization ?? store.usage?.claude?.fiveHour?.utilization
    }

    // MARK: Slash state

    private var slashTyped: Bool {
        let t = draft.text
        return t.hasPrefix("/") && !t.contains(" ") && !t.contains("\n")
    }

    private var showSuggestions: Bool {
        !commandsDismissed && !commands.isEmpty && (isCommandPickerPresented || slashTyped)
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { slashTyped ? String(draft.text.dropFirst()) : commandSearch },
            set: { v in
                if slashTyped { draft.text = "/" + v } else { commandSearch = v }
            }
        )
    }

    private var suggestionsMaxHeight: CGFloat {
        let h = Self.screenHeight
        return min(360, max(160, h * 0.45))
    }

    private static var screenHeight: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.bounds.height ?? 800
    }

    private func closeSuggestions() {
        isCommandPickerPresented = false
        commandSearch = ""
        if slashTyped { draft.text = "" }
        commandsDismissed = true
    }

    private func selectCommand(_ cleanName: String) {
        draft.selectedCommand = cleanName
        isCommandPickerPresented = false
        commandSearch = ""
        if draft.text.hasPrefix("/") { draft.text = "" }
        isFocused = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 8) {
            if sessionId == nil {
                chatModeSegmentedControl
            }
            composerContainer
        }
        // Suggestions float above the composer; they never take layout space or push the chat off-screen.
        .overlay(alignment: .top) {
            if showSuggestions {
                CommandSuggestionsView(
                    agentId: currentAgentId,
                    commands: commands,
                    onSelect: { selectCommand($0) },
                    onDismiss: { closeSuggestions() },
                    query: queryBinding,
                    maxHeight: suggestionsMaxHeight,
                    showsSearchField: !slashTyped
                )
                .frame(maxWidth: .infinity)
                .alignmentGuide(.top) { d in d[.bottom] + 8 }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.smooth, value: showSuggestions)
        .animation(.smooth, value: sessionId == nil)
        .photosPicker(isPresented: $isPhotosPickerPresented, selection: $selectedPhotos, matching: .images)
        .onChange(of: selectedPhotos) { _, newItems in
            guard !newItems.isEmpty else { return }
            let picked = newItems
            let target = draft
            selectedPhotos = []
            for item in picked {
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        ui.toast = "Couldn't load that photo"
                        return
                    }
                    let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    target.addImage(data: data, name: "photo-\(UUID().uuidString.prefix(6)).\(ext)", mime: mime,
                                    client: client, onError: { ui.toast = $0 })
                }
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            let target = draft
            ComposerCameraPicker { image in
                target.addCameraImage(image, client: client, onError: { ui.toast = $0 })
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): draft.addFiles(urls, client: client, onError: { ui.toast = $0 })
            case .failure(let error): ui.toast = "Couldn't pick file: \(error.localizedDescription)"
            }
        }
        .fullScreenCover(isPresented: $isVoiceModePresented) {
            VoiceModeView(sessionId: sessionId, isPresented: $isVoiceModePresented)
        }
        .sheet(item: $promptEditorSeed) { seed in
            PromptEditorSheet(seedText: seed.text)
        }
        .onReceive(NotificationCenter.default.publisher(for: .linkupComposerSetText)) { note in
            if let s = note.object as? String {
                draft.text = s
                isFocused = true
            }
        }
        .onChange(of: isWorking) { _, working in
            if working { draft.clearSending() } else { draft.clearStopping() }
        }
        .onChange(of: sessionId) { _, _ in
            dictation?.stop()
            isCommandPickerPresented = false
            commandsDismissed = false
            commandSearch = ""
        }
        .onChange(of: draft.text) { _, new in
            if !new.hasPrefix("/") { commandsDismissed = false }
        }
        .onDisappear {
            dictation?.stop()
        }
    }

    // MARK: Subviews

    private func modeButton(_ mode: String, title: String, symbol: String) -> some View {
        let on = draftMode == mode
        return Button {
            draftMode = mode
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(Theme.sans(13, weight: on ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(on ? Theme.text : Theme.secondaryText)
            .background { if on { Capsule().fill(Theme.elevated) } }
            .contentShape(Capsule())
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var chatModeSegmentedControl: some View {
        GlassEffectContainer {
            HStack(spacing: 4) {
                modeButton("agent", title: "Agent", symbol: "sparkles")
                modeButton("chat", title: "Chat", symbol: "bubble.left.and.text.bubble.right")
            }
            .padding(3)
        }
    }

    private var composerContainer: some View {
        VStack(spacing: 8) {
            if !draft.attachments.isEmpty {
                attachmentStrip
            }

            if isFocused && draft.text.isEmpty && draft.selectedCommand == nil && !isCompact {
                ComposerPromptLibraryView(
                    onSelect: { draft.text = $0 },
                    onAdd: { promptEditorSeed = PromptEditorSeed(text: draft.text) }
                )
                .frame(height: 48)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            HStack(alignment: .center, spacing: 6) {
                if let cmd = draft.selectedCommand {
                    HStack(spacing: 2) {
                        Text("/\(cmd)")
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.leading, 9)
                        Button {
                            draft.selectedCommand = nil
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Remove command /\(cmd)")
                    }
                    .background(Theme.accent.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(Theme.accent.opacity(0.38), lineWidth: 1))
                    .transition(.scale.combined(with: .opacity))
                }

                TextField(placeholder, text: textBinding, axis: .vertical)
                    .font(Theme.sans(17))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1...(isCompact ? 3 : 8))
                    .tint(Theme.accent)
                    .focused($isFocused)
                    .disabled(draft.isCreating)
                    .environment(\.layoutDirection, draft.text.dominantLayoutDirection)
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        // Hardware keyboard: Return sends, Shift+Return inserts a newline.
                        if press.modifiers.contains(.shift) { return .ignored }
                        guard !draft.isEmpty else { return .ignored }
                        send()
                        return .handled
                    }
            }
            .padding(.horizontal, 14)
            .padding(.top, draft.attachments.isEmpty ? 10 : 2)
            .padding(.bottom, 2)

            if let reason = disabledReason {
                Text(reason)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    plusMenuButton
                    slashButton
                    modelPillButton
                    Spacer(minLength: 0)
                    micButton
                    primaryButton
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .padding(4)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.hairline, lineWidth: 1))
    }

    private var disabledReason: String? {
        switch client.state {
        case .connected: break
        case .connecting: return "Connecting to your PC\u{2026}"
        default: return "Not connected to your PC"
        }
        if draft.hasFailedUpload { return "An attachment failed to upload. Tap it to retry, or remove it." }
        return nil
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(draft.attachments) { item in
                    if item.isImage { imageThumbnailView(item) } else { fileCapsuleView(item) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    private func removeButton(_ item: ComposerAttachment) -> some View {
        Button {
            draft.remove(item.id)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.white, Color.black.opacity(0.65))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Remove \(item.name)")
    }

    private func retryUpload(_ item: ComposerAttachment) {
        guard item.uploadFailed else { return }
        draft.retry(item.id, client: client, onError: { ui.toast = $0 })
    }

    private func imageThumbnailView(_ item: ComposerAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if let thumb = item.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.elevated)
                        .frame(width: 60, height: 60)
                        .overlay { Image(systemName: "photo").foregroundStyle(Theme.secondaryText) }
                }
                if item.isUploading {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.background.opacity(0.6))
                        .frame(width: 60, height: 60)
                        .overlay { ProgressView().tint(Theme.text) }
                } else if item.uploadFailed {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.danger.opacity(0.35))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.text)
                        }
                }
            }
            .frame(width: 60, height: 60)
            .padding(.top, 4)
            .contentShape(Rectangle())
            .onTapGesture { retryUpload(item) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.uploadFailed ? "\(item.name), upload failed. Tap to retry"
                                : (item.isUploading ? "\(item.name), uploading" : item.name))
            .accessibilityAddTraits(.isButton)

            removeButton(item)
                .offset(x: 14, y: -14)
        }
        .frame(width: 66, height: 68)
    }

    private func fileCapsuleView(_ item: ComposerAttachment) -> some View {
        HStack(spacing: 6) {
            if item.isUploading {
                ProgressView().tint(Theme.text).scaleEffect(0.75)
            } else if item.uploadFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.danger)
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(item.name)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
            Button {
                draft.remove(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Remove \(item.name)")
        }
        .padding(.leading, 12)
        .background(Theme.surface, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { retryUpload(item) }
    }

    private var plusMenuButton: some View {
        Menu {
            Button { isPhotosPickerPresented = true } label: { Label("Photos", systemImage: "photo") }
            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    isCameraPresented = true
                } else {
                    ui.toast = "Camera isn't available on this device"
                }
            } label: { Label("Camera", systemImage: "camera") }
            Button { isFileImporterPresented = true } label: { Label("Files", systemImage: "folder") }
            if !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                Button {
                    promptEditorSeed = PromptEditorSeed(text: draft.text)
                } label: { Label("Save text as prompt", systemImage: "text.badge.plus") }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Add attachment")
    }

    private var slashButton: some View {
        Button {
            if commands.isEmpty {
                ui.toast = "\(agentName) has no slash commands"
                return
            }
            commandsDismissed = false
            isCommandPickerPresented.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text("/")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(isCommandPickerPresented ? Theme.accent : Theme.text)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Slash commands")
    }

    private var modelPillButton: some View {
        Button {
            ui.isShowingModelPicker = true
        } label: {
            let info = modelPillText
            HStack(spacing: 5) {
                if let used = ringUtilization {
                    UsageRingBadge(utilization: used, size: 16)
                        .padding(.trailing, 2)
                }
                Text(info.name)
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let effort = info.effort {
                    Text(effort)
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Capsule())
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .layoutPriority(-1)
        .accessibilityLabel("Model: \(modelPillText.name)\(modelPillText.effort.map { ", \($0) effort" } ?? "")")
    }

    private var micButton: some View {
        Button {
            toggleDictation()
        } label: {
            Image(systemName: isListening ? "mic.fill" : "mic")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(isListening ? Color.white : Theme.text)
                .symbolEffect(.pulse, isActive: isListening)
                .frame(width: 44, height: 44)
                .background { if isListening { Circle().fill(Theme.accent) } }
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(draft.isCreating)
        .accessibilityLabel(isListening ? "Stop dictation" : "Dictate")
    }

    private enum PrimaryMode { case send, stop, voice, busy }

    private var primaryMode: PrimaryMode {
        if draft.isCreating { return .busy }
        if !draft.isEmpty { return .send }
        if isWorking || draft.isSending { return .stop }
        return .voice
    }

    private var primaryButton: some View {
        let mode = primaryMode
        return Button {
            switch mode {
            case .send: send()
            case .stop: stop()
            case .voice:
                dictation?.stop()
                isVoiceModePresented = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .busy: break
            }
        } label: {
            ZStack {
                Circle().fill(Color.white)
                switch mode {
                case .send:
                    if draft.isUploading {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.black)
                    }
                case .stop:
                    if draft.isStopping {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                    }
                case .voice:
                    Image(systemName: "waveform")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.black)
                case .busy:
                    ProgressView().tint(.black)
                }
            }
            .frame(width: 44, height: 44)
            .opacity(mode == .send && (draft.isUploading || draft.hasFailedUpload) ? 0.5 : 1)
            .contentShape(Circle())
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(mode == .busy || (mode == .stop && draft.isStopping))
        .accessibilityLabel(mode == .send ? (isWorking ? "Send (queued)" : "Send")
                            : mode == .stop ? "Stop" : mode == .voice ? "Voice mode" : "Starting chat")
    }

    // MARK: Actions

    private func toggleDictation() {
        let engine: ComposerDictation
        if let d = dictation { engine = d } else {
            engine = ComposerDictation()
            dictation = engine
        }
        let target = draft
        if engine.isListening {
            engine.stop()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            baseDictationText = target.text.isEmpty ? "" : (target.text.hasSuffix(" ") ? target.text : target.text + " ")
            let base = baseDictationText
            engine.start { spoken in
                target.text = base + spoken
            } onError: { errorMsg in
                ui.toast = errorMsg
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func stop() {
        guard let sid = sessionId else { return }
        draft.markStopping()
        draft.clearSending()
        store.interrupt(sid)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func send() {
        let d = draft
        guard !d.isCreating, !d.isEmpty else { return }
        dictation?.stop()

        guard client.state == .connected else {
            ui.toast = "Not connected to your PC"
            return
        }
        guard !d.isUploading else {
            ui.toast = "Still uploading attachments\u{2026}"
            return
        }
        guard !d.hasFailedUpload else {
            ui.toast = "An attachment failed to upload. Tap it to retry, or remove it."
            return
        }

        let trimmed = d.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var sendText = trimmed
        if let cmd = d.selectedCommand {
            sendText = trimmed.isEmpty ? "/\(cmd)" : "/\(cmd) \(trimmed)"
        }
        let records = d.attachments.compactMap { $0.uploadedRecord }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if let sid = sessionId {
            d.clear()
            d.markSending()
            store.send(sendText, to: sid, attachments: records)
            return
        }

        // New chat: lock the composer while the session is created; keep the draft if it fails.
        d.isCreating = true
        let mode = draftMode
        let agentId = ui.draftAgent
        let modelId = ui.draftModel
        let effort = ui.draftEffort
        let project = ui.draftProject
        Task {
            do {
                let created: SessionInfo
                if mode == "chat" {
                    created = try await store.createChat(agent: agentId, model: modelId)
                } else {
                    let agent = store.agent(agentId)
                    let model = agent?.model(modelId ?? agent?.defaultModel)
                    let sendEffort = (model?.efforts?.isEmpty == false) ? effort : nil
                    let permMode = (agentId == "claude") ? UserDefaults.standard.string(forKey: "draftPermissionMode") : nil
                    created = try await store.create(agent: agentId, model: modelId, effort: sendEffort,
                                                     cwd: project, permissionMode: permMode)
                }
                d.clear()
                d.isCreating = false
                store.send(sendText, to: created.id, attachments: records)
                // Follow only if the user is still on the new-chat screen (ChatView subscribes to the session).
                if ui.currentSessionId == nil {
                    ui.openSession(created.id)
                }
            } catch {
                d.isCreating = false
                ui.toast = "Couldn't start the chat: \(error.localizedDescription)"
            }
        }
    }
}

/// Agent + model + effort picker sheet with live catalogs.
struct ModelPickerSheet: View {
    let sessionId: String?

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDraftPermMode = UserDefaults.standard.string(forKey: "draftPermissionMode") ?? "default"
    @State private var confirmFullAccess = false
    @State private var openUsageOnDisappear = false

    private var currentAgentId: String {
        if let sid = sessionId, let s = store.session(sid) { return s.agent }
        return ui.draftAgent
    }

    private var currentAgent: AgentInfo? { store.agent(currentAgentId) }

    private var currentSelectedModelId: String? {
        if let sid = sessionId, let s = store.session(sid) { return s.model ?? currentAgent?.defaultModel }
        return ui.draftModel ?? currentAgent?.defaultModel
    }

    private var currentSelectedModel: ModelInfo? { currentAgent?.model(currentSelectedModelId) }

    private var currentEffort: String? {
        if let sid = sessionId, let s = store.session(sid) { return s.effort }
        return ui.draftEffort
    }

    private var currentPermissionMode: String {
        if let sid = sessionId, let s = store.session(sid) { return s.permissionMode ?? "default" }
        return selectedDraftPermMode
    }

    private var currentProjectName: String {
        if let path = ui.draftProject, !path.isEmpty {
            return store.projects.first(where: { $0.path == path })?.name ?? URL(fileURLWithPath: path).lastPathComponent
        }
        return "Default directory"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Model", onClose: {
                ui.isShowingModelPicker = false
                dismiss()
            })

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let err = store.lastError, !err.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.danger)
                            Text(err).font(Theme.sans(13)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    agentSwitcherSection
                    modelsListSection
                    effortSection
                    permissionsSection
                    projectSection
                    footerSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .refreshable {
                await store.refreshCatalog(force: true)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
        .task {
            await store.refreshCatalog(force: false)
            if sessionId == nil { await store.loadProjects() }
        }
        .onDisappear {
            if openUsageOnDisappear {
                openUsageOnDisappear = false
                ui.isShowingUsage = true
            }
        }
        .confirmationDialog("Full access?", isPresented: $confirmFullAccess, titleVisibility: .visible) {
            Button("Allow full access", role: .destructive) { applyPermission("bypassPermissions") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The agent will run tools and edit files on your PC without asking first.")
        }
    }

    // MARK: Sections

    private var agentSwitcherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassEffectContainer {
                HStack(spacing: 8) {
                    ForEach(AgentKind.allCases, id: \.self) { kind in
                        let agent = store.agent(kind.rawValue)
                        let isAvailable = agent?.available ?? true
                        let isSelected = (currentAgentId == kind.rawValue)

                        Button {
                            guard isAvailable, !isSelected else { return }
                            // Changing agent in a running session starts a fresh chat with that agent.
                            ui.draftAgent = kind.rawValue
                            ui.draftModel = agent?.defaultModel
                            ui.draftEffort = nil
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if sessionId != nil {
                                ui.isShowingModelPicker = false
                                dismiss()
                                ui.newChat()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: kind.symbol).font(.system(size: 14, weight: .medium))
                                Text(kind.title)
                                    .font(Theme.sans(14, weight: isSelected ? .semibold : .regular))
                                    .lineLimit(1)
                                if !isAvailable {
                                    Text("Offline")
                                        .font(Theme.sans(11, weight: .medium))
                                        .foregroundStyle(Theme.danger)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
                            .background { if isSelected { Capsule().fill(Theme.elevated) } }
                            .contentShape(Capsule())
                        }
                        .disabled(!isAvailable)
                        .opacity(isAvailable ? 1.0 : 0.45)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }

            if sessionId != nil {
                Text("Picking another agent starts a new chat with it.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 4)
            }

            if let error = currentAgent?.error, currentAgent?.available == false {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.danger)
                    Text(error).font(Theme.sans(12)).foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var modelsListSection: some View {
        VStack(spacing: 0) {
            let models = currentAgent?.models ?? []
            if models.isEmpty {
                HStack {
                    Text(currentAgent?.available == false ? "Agent is offline" : "No models available")
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                }
                .padding(16)
            } else {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    let isSelected = (model.id == currentSelectedModelId)
                    Button {
                        if let sid = sessionId {
                            store.update(sid, model: model.id)
                        } else {
                            ui.draftModel = model.id
                            // Drop an effort the new model doesn't support.
                            if let e = ui.draftEffort,
                               !(model.efforts ?? []).contains(where: { $0.lowercased() == e.lowercased() }) {
                                ui.draftEffort = nil
                            }
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.name).font(Theme.sans(17)).foregroundStyle(Theme.text)
                                if let desc = model.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(Theme.sans(14))
                                        .foregroundStyle(Theme.secondaryText)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])

                    if index < models.count - 1 {
                        Divider().overlay(Theme.hairline).padding(.horizontal, 16)
                    }
                }
            }
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var effortSection: some View {
        if let efforts = currentSelectedModel?.efforts, !efforts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Effort")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)

                GlassEffectContainer {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(efforts, id: \.self) { effort in
                                let isSelected = (currentEffort?.lowercased() == effort.lowercased())
                                Button {
                                    if let sid = sessionId {
                                        store.update(sid, effort: effort)
                                    } else {
                                        ui.draftEffort = effort
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    HStack(spacing: 5) {
                                        if isSelected {
                                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                        }
                                        Text(effort.capitalized)
                                            .font(Theme.sans(14, weight: isSelected ? .semibold : .regular))
                                    }
                                    .foregroundStyle(isSelected ? Color.black : Theme.secondaryText)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 44)
                                    .background { if isSelected { Capsule().fill(Theme.accent) } }
                                    .contentShape(Capsule())
                                }
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                    }
                }
            }
        }
    }

    private func applyPermission(_ mode: String) {
        if let sid = sessionId {
            store.update(sid, permissionMode: mode)
        } else {
            UserDefaults.standard.set(mode, forKey: "draftPermissionMode")
            selectedDraftPermMode = mode
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @ViewBuilder
    private var permissionsSection: some View {
        if currentAgentId == "claude" {
            let modes = currentAgent?.permissionModes ?? ["default", "acceptEdits", "plan", "bypassPermissions"]
            VStack(alignment: .leading, spacing: 8) {
                Text("Permissions")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)

                Menu {
                    ForEach(modes, id: \.self) { mode in
                        Button {
                            if mode == "bypassPermissions" && mode != currentPermissionMode {
                                confirmFullAccess = true
                            } else {
                                applyPermission(mode)
                            }
                        } label: {
                            HStack {
                                Text(permissionLabel(mode))
                                if mode == currentPermissionMode { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    pickerRow(symbol: "lock.shield", text: permissionLabel(currentPermissionMode))
                }
            }
        }
    }

    @ViewBuilder
    private var projectSection: some View {
        if sessionId == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Project")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)

                Menu {
                    Button {
                        ui.draftProject = nil
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Text("Default directory")
                            if ui.draftProject == nil { Image(systemName: "checkmark") }
                        }
                    }
                    ForEach(store.projects) { proj in
                        Button {
                            ui.draftProject = proj.path
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack {
                                Text(proj.name)
                                if ui.draftProject == proj.path { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    pickerRow(symbol: "folder", text: currentProjectName)
                }
            }
        }
    }

    private func pickerRow(symbol: String, text: String) -> some View {
        HStack {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
            Text(text)
                .font(Theme.sans(15))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footerSection: some View {
        HStack {
            if let account = currentAgent?.accountLabel, !account.isEmpty {
                Text(account)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button {
                // Present Usage only once this sheet is gone, otherwise SwiftUI drops the second presentation.
                openUsageOnDisappear = true
                ui.isShowingModelPicker = false
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Text("Usage").font(Theme.sans(14, weight: .medium))
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.link)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .padding(.top, 4)
    }

    private func permissionLabel(_ mode: String) -> String {
        switch mode {
        case "default": return "Ask before acting"
        case "acceptEdits": return "Auto-accept edits"
        case "plan": return "Plan only"
        case "bypassPermissions": return "Full access"
        default: return mode.capitalized
        }
    }
}
