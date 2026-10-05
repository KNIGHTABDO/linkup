import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Bottom of the chat: rounded glass input container with attachments, multiline text,
/// model pill, dictation, and send/stop.
struct ComposerView: View {
    let sessionId: String?

    @Environment(SessionStore.self) private var store
    @Environment(LinkupClient.self) private var client
    @Environment(UIState.self) private var ui

    @AppStorage("draftMode") private var draftMode: String = "agent"

    @State private var text = ""
    @State private var attachments: [ComposerAttachment] = []
    @State private var dictation = ComposerDictation()
    @State private var baseDictationText = ""
    @State private var isPulsingMic = false
    @FocusState private var isFocused: Bool

    // Slash command picker & token chip
    @State private var isCommandPickerPresented = false
    @State private var selectedCommand: String? = nil

    // Voice mode presentation
    @State private var isVoiceModePresented = false

    // Pickers presentation
    @State private var isPhotosPickerPresented = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var isFileImporterPresented = false

    private var isWorking: Bool {
        guard let sid = sessionId else { return false }
        return store.transcript(for: sid).isWorking
    }

    private var isUploadingAnyAttachment: Bool {
        attachments.contains { $0.isUploading }
    }

    private var hasContent: Bool {
        selectedCommand != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var currentAgentId: String {
        if let sid = sessionId, let s = store.session(sid) {
            return s.agent
        } else {
            return ui.draftAgent
        }
    }

    private var agentName: String {
        let agentId = currentAgentId
        if let name = store.agent(agentId)?.name, !name.isEmpty {
            return name
        }
        return AgentKind(rawValue: agentId)?.title ?? "Claude Code"
    }

    private var placeholder: String {
        if let _ = selectedCommand {
            return "Add arguments (optional)\u{2026}"
        }
        if sessionId == nil {
            if draftMode == "chat" {
                return "Ask anything \u{2014} places, weather, recipes\u{2026}"
            } else {
                return "Chat with \(agentName)"
            }
        } else {
            return "Reply to \(agentName)"
        }
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
        // "Default (recommended)" reads better as the model it resolves to ("Opus 5.5", from its description).
        let resolvedName = model?.description?.components(separatedBy: "\u{00B7}").first?.trimmingCharacters(in: .whitespaces)
        let displayName = (model?.id == "default" ? resolvedName : nil) ?? model?.name ?? effectiveModelId ?? "Model"
        let effortDisplay = (effort?.isEmpty == false) ? effort?.capitalized : nil
        return (displayName, effortDisplay)
    }

    private var showSuggestions: Bool {
        isCommandPickerPresented || (text.hasPrefix("/") && !text.contains(" ") && !text.contains("\n"))
    }

    private func selectCommand(_ cleanName: String) {
        selectedCommand = cleanName
        isCommandPickerPresented = false
        if text.hasPrefix("/") {
            text = ""
        }
        isFocused = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        VStack(spacing: 8) {
            if sessionId == nil {
                chatModeSegmentedControl
            }

            if showSuggestions {
                CommandSuggestionsView(
                    agentId: currentAgentId,
                    commands: store.agent(currentAgentId)?.commands ?? [],
                    onSelect: { cleanName in
                        selectCommand(cleanName)
                    },
                    onDismiss: {
                        isCommandPickerPresented = false
                        if text == "/" {
                            text = ""
                        }
                    },
                    initialQuery: text.hasPrefix("/") ? String(text.dropFirst()) : ""
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            composerContainer
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.smooth, value: showSuggestions)
        .animation(.smooth, value: sessionId == nil)
        .photosPicker(isPresented: $isPhotosPickerPresented, selection: $selectedPhotos, matching: .images)
        .onChange(of: selectedPhotos) { _, newItems in
            guard !newItems.isEmpty else { return }
            let picked = newItems
            selectedPhotos = []
            for item in picked {
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                        let name = "photo-\(UUID().uuidString.prefix(6)).\(ext)"
                        let image = UIImage(data: data)
                        addAttachment(name: name, mime: mime, data: data, thumbnail: image)
                    }
                }
            }
        }
        .sheet(isPresented: $isCameraPresented) {
            ComposerCameraPicker { image in
                handleCameraCaptured(image)
            }
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleFilesSelected(result)
        }
        .fullScreenCover(isPresented: $isVoiceModePresented) {
            VoiceModeView(sessionId: sessionId, isPresented: $isVoiceModePresented)
        }
        .onDisappear {
            dictation.stop()
        }
    }

    // MARK: Subviews

    private var chatModeSegmentedControl: some View {
        GlassEffectContainer {
            HStack(spacing: 4) {
                Button {
                    draftMode = "agent"
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Agent")
                            .font(Theme.sans(13, weight: draftMode == "agent" ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(draftMode == "agent" ? Theme.text : Theme.secondaryText)
                    .background {
                        if draftMode == "agent" {
                            Capsule().fill(Theme.elevated)
                        }
                    }
                }
                .glassEffect(.regular.interactive(), in: .capsule)

                Button {
                    draftMode = "chat"
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Chat")
                            .font(Theme.sans(13, weight: draftMode == "chat" ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(draftMode == "chat" ? Theme.text : Theme.secondaryText)
                    .background {
                        if draftMode == "chat" {
                            Capsule().fill(Theme.elevated)
                        }
                    }
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(3)
        }
    }

    private var composerContainer: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                attachmentStrip
            }

            if isFocused {
                ComposerPromptLibraryView(currentText: text) { promptText in
                    text = promptText
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(alignment: .center, spacing: 6) {
                if let cmd = selectedCommand {
                    HStack(spacing: 5) {
                        Text("/\(cmd)")
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Button {
                            selectedCommand = nil
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.18), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Theme.accent.opacity(0.38), lineWidth: 1)
                    )
                    .transition(.scale.combined(with: .opacity))
                }

                TextField(placeholder, text: $text, axis: .vertical)
                    .font(Theme.sans(17))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1...8)
                    .tint(Theme.accent)
                    .focused($isFocused)
            }
            .padding(.horizontal, 14)
            .padding(.top, attachments.isEmpty ? 10 : 2)
            .padding(.bottom, 2)

            GlassEffectContainer {
                HStack(spacing: 8) {
                    plusMenuButton
                    slashButton
                    modelPillButton
                    Spacer()
                    micButton
                    primaryButton
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { item in
                    if item.isImage {
                        imageThumbnailView(item)
                    } else {
                        fileCapsuleView(item)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    private func imageThumbnailView(_ item: ComposerAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
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
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(Theme.secondaryText)
                    }
            }

            if item.isUploading {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 60, height: 60)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }

            Button {
                removeAttachment(id: item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.white, Color.black.opacity(0.65))
            }
            .offset(x: 4, y: -4)
        }
    }

    private func fileCapsuleView(_ item: ComposerAttachment) -> some View {
        HStack(spacing: 6) {
            if item.isUploading {
                ProgressView()
                    .tint(Theme.text)
                    .scaleEffect(0.75)
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }

            Text(item.name)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Button {
                removeAttachment(id: item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.elevated, in: Capsule())
    }

    private var plusMenuButton: some View {
        Menu {
            Button {
                isPhotosPickerPresented = true
            } label: {
                Label("Photos", systemImage: "photo")
            }
            Button {
                isCameraPresented = true
            } label: {
                Label("Camera", systemImage: "camera")
            }
            Button {
                isFileImporterPresented = true
            } label: {
                Label("Files", systemImage: "folder")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var slashButton: some View {
        Button {
            isCommandPickerPresented.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text("/")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
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
                if currentAgentId == "claude",
                   let used = store.usage?.claudePlan?.fiveHour?.utilization ?? store.usage?.claude?.fiveHour?.utilization {
                    UsageRingBadge(utilization: used, size: 16)
                        .padding(.trailing, 2)
                }
                Text(info.name)
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.text)
                if let effort = info.effort {
                    Text(effort)
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Capsule())
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var micButton: some View {
        Button {
            toggleDictation()
        } label: {
            Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(dictation.isListening ? Color.white : Theme.text)
                .frame(width: 44, height: 44)
                .background {
                    if dictation.isListening {
                        Circle().fill(Theme.accent)
                    }
                }
                .scaleEffect(isPulsingMic ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsingMic)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .onChange(of: dictation.isListening) { _, listening in
            isPulsingMic = listening
        }
    }

    private var primaryButton: some View {
        Group {
            if isWorking {
                Button {
                    if let sid = sessionId {
                        store.interrupt(sid)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white))
                }
            } else if hasContent {
                Button {
                    handleSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white))
                        .opacity(isUploadingAnyAttachment ? 0.4 : 1.0)
                }
                .disabled(isUploadingAnyAttachment)
            } else {
                Button {
                    isVoiceModePresented = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white))
                }
            }
        }
    }

    // MARK: Actions

    private func toggleDictation() {
        if dictation.isListening {
            dictation.stop()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            baseDictationText = text.isEmpty ? "" : (text.hasSuffix(" ") ? text : text + " ")
            dictation.start { spoken in
                text = baseDictationText + spoken
            } onError: { errorMsg in
                ui.toast = errorMsg
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func handleSend() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasContent else { return }
        guard !isUploadingAnyAttachment else { return }

        if dictation.isListening {
            dictation.stop()
        }

        var sendText = trimmed
        if let cmd = selectedCommand {
            sendText = trimmed.isEmpty ? "/\(cmd)" : "/\(cmd) \(trimmed)"
            selectedCommand = nil
        }

        let itemsToSend = attachments
        text = ""
        attachments = []

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                var uploadedList: [[String: JSONValue]] = []
                for item in itemsToSend {
                    if let record = item.uploadedRecord {
                        uploadedList.append(record)
                    } else {
                        let record = try await client.upload(data: item.data, name: item.name, mime: item.mime)
                        uploadedList.append(record)
                    }
                }

                let targetSessionId: String
                if let sid = sessionId {
                    targetSessionId = sid
                } else if draftMode == "chat" {
                    let s = try await store.createChat(agent: ui.draftAgent, model: ui.draftModel)
                    ui.currentSessionId = s.id
                    store.open(s.id)
                    targetSessionId = s.id
                } else {
                    let permMode = (ui.draftAgent == "claude") ? UserDefaults.standard.string(forKey: "draftPermissionMode") : nil
                    let s = try await store.create(
                        agent: ui.draftAgent,
                        model: ui.draftModel,
                        effort: ui.draftEffort,
                        cwd: ui.draftProject,
                        permissionMode: permMode
                    )
                    ui.currentSessionId = s.id
                    store.open(s.id)
                    targetSessionId = s.id
                }

                store.send(sendText, to: targetSessionId, attachments: uploadedList)
            } catch {
                ui.toast = error.localizedDescription
            }
        }
    }

    private func addAttachment(name: String, mime: String, data: Data, thumbnail: UIImage?) {
        let id = UUID()
        let att = ComposerAttachment(
            id: id,
            name: name,
            mime: mime,
            data: data,
            thumbnail: thumbnail,
            isUploading: true
        )
        attachments.append(att)

        Task {
            do {
                let record = try await client.upload(data: data, name: name, mime: mime)
                if let idx = attachments.firstIndex(where: { $0.id == id }) {
                    attachments[idx].uploadedRecord = record
                    attachments[idx].isUploading = false
                }
            } catch {
                if let idx = attachments.firstIndex(where: { $0.id == id }) {
                    attachments[idx].isUploading = false
                    attachments[idx].uploadFailed = true
                }
                ui.toast = "Failed to upload \(name): \(error.localizedDescription)"
            }
        }
    }

    private func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    private func handleCameraCaptured(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let name = "camera-\(Int(Date().timeIntervalSince1970)).jpg"
        addAttachment(name: name, mime: "image/jpeg", data: data, thumbnail: image)
    }

    private func handleFilesSelected(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { continue }
                let name = url.lastPathComponent
                let ext = url.pathExtension
                let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
                let isImg = mime.hasPrefix("image/")
                let thumbnail = isImg ? UIImage(data: data) : nil
                addAttachment(name: name, mime: mime, data: data, thumbnail: thumbnail)
            }
        case .failure(let error):
            ui.toast = "Failed to pick file: \(error.localizedDescription)"
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

    private var currentAgentId: String {
        if let sid = sessionId, let s = store.session(sid) {
            return s.agent
        }
        return ui.draftAgent
    }

    private var currentAgent: AgentInfo? {
        store.agent(currentAgentId)
    }

    private var currentSelectedModelId: String? {
        if let sid = sessionId, let s = store.session(sid) {
            return s.model ?? currentAgent?.defaultModel
        }
        return ui.draftModel ?? currentAgent?.defaultModel
    }

    private var currentSelectedModel: ModelInfo? {
        currentAgent?.model(currentSelectedModelId)
    }

    private var currentEffort: String? {
        if let sid = sessionId, let s = store.session(sid) {
            return s.effort
        }
        return ui.draftEffort
    }

    private var currentPermissionMode: String {
        if let sid = sessionId, let s = store.session(sid) {
            return s.permissionMode ?? "default"
        }
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
            sheetTopBar

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
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
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surface)
        .task {
            if sessionId == nil {
                await store.loadProjects()
            }
        }
    }

    // MARK: Sections

    private var sheetTopBar: some View {
        HStack {
            Button {
                ui.isShowingModelPicker = false
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 32, height: 32)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            Text("Model")
                .font(Theme.sans(17, weight: .semibold))
                .foregroundStyle(Theme.text)

            Spacer()

            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var agentSwitcherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassEffectContainer {
                HStack(spacing: 8) {
                    ForEach(AgentKind.allCases, id: \.self) { kind in
                        let agent = store.agent(kind.rawValue)
                        let isAvailable = agent?.available ?? true
                        let isSelected = (currentAgentId == kind.rawValue)

                        Button {
                            guard isAvailable else { return }
                            if sessionId == nil {
                                ui.draftAgent = kind.rawValue
                                ui.draftModel = agent?.defaultModel
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: kind.symbol)
                                    .font(.system(size: 14, weight: .medium))
                                Text(kind.title)
                                    .font(Theme.sans(14, weight: isSelected ? .semibold : .regular))
                                if !isAvailable {
                                    Text("Offline")
                                        .font(Theme.sans(11, weight: .medium))
                                        .foregroundStyle(Theme.danger)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
                            .background {
                                if isSelected {
                                    Capsule().fill(Theme.elevated)
                                }
                            }
                        }
                        .disabled(!isAvailable || (sessionId != nil && !isSelected))
                        .opacity(isAvailable ? 1.0 : 0.45)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
            }

            if let error = currentAgent?.error, currentAgent?.available == false {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.danger)
                    Text(error)
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.secondaryText)
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
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.name)
                                    .font(Theme.sans(17))
                                    .foregroundStyle(Theme.text)
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < models.count - 1 {
                        Divider()
                            .overlay(Theme.hairline)
                            .padding(.horizontal, 16)
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
                                    Text(effort.capitalized)
                                        .font(Theme.sans(14, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background {
                                            if isSelected {
                                                Capsule().fill(Theme.elevated)
                                            }
                                        }
                                }
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                        }
                    }
                }
            }
        }
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
                            if let sid = sessionId {
                                store.update(sid, permissionMode: mode)
                            } else {
                                UserDefaults.standard.set(mode, forKey: "draftPermissionMode")
                                selectedDraftPermMode = mode
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack {
                                Text(permissionLabel(mode))
                                if mode == currentPermissionMode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.secondaryText)
                        Text(permissionLabel(currentPermissionMode))
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
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
                            if ui.draftProject == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    ForEach(store.projects) { proj in
                        Button {
                            ui.draftProject = proj.path
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack {
                                Text(proj.name)
                                if ui.draftProject == proj.path {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "folder")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.secondaryText)
                        Text(currentProjectName)
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
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
                ui.isShowingModelPicker = false
                dismiss()
                ui.isShowingUsage = true
            } label: {
                HStack(spacing: 4) {
                    Text("Usage")
                        .font(Theme.sans(14, weight: .medium))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.link)
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
