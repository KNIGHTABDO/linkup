import SwiftUI
import AVFoundation
import Speech

enum VoiceModePhase {
    case listening
    case thinking
    case speaking

    var accessibilityName: String {
        switch self {
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        }
    }
}

/// Full-screen voice conversation:
/// - Listens with ComposerDictation (language from "linkupSpeechLanguage"), reacts to mic level via the orb.
/// - 1.5 s of silence auto-sends, or tap "Send".
/// - Streams the agent's reply from the transcript and speaks it sentence by sentence with AVSpeechSynthesizer.
/// - Skips code blocks and ```linkup-card blocks; keeps listening again after each reply.
/// - Tapping the orb while the agent speaks skips the speech only; "Stop agent" interrupts the turn itself.
/// - Permission requests from the agent are answered inline.
struct VoiceModeView: View {
    let sessionId: String?
    @Binding var isPresented: Bool

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var activeSessionId: String? = nil
    @State private var phase: VoiceModePhase = .listening
    @State private var liveSpokenText: String = ""
    @State private var agentReplyText: String = ""
    @State private var voiceError: String? = nil
    @State private var isCommitting = false
    @State private var dictation = ComposerDictation()
    @State private var speechCoordinator = VoiceSpeechCoordinator()

    @State private var silenceTask: Task<Void, Never>? = nil
    @State private var monitorTask: Task<Void, Never>? = nil

    private var isCompact: Bool { verticalSizeClass == .compact }
    private var orbScale: CGFloat { isCompact ? 0.55 : 1 }

    private var currentSessionId: String? { activeSessionId ?? sessionId }

    private var currentAgentId: String {
        if let sid = currentSessionId, let s = store.session(sid) {
            return s.agent
        }
        return ui.draftAgent
    }

    private var agentName: String {
        if let name = store.agent(currentAgentId)?.name, !name.isEmpty {
            return name
        }
        return AgentKind(rawValue: currentAgentId)?.title ?? "Claude Code"
    }

    private var pendingPermission: PermissionRequest? {
        guard let sid = currentSessionId else { return nil }
        return store.transcript(for: sid).pendingPermissions.first { $0.allowed == nil }
    }

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)
                    .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: isCompact ? 8 : 24) {
                        bigAnimatedOrb
                            .padding(.top, isCompact ? 4 : 20)

                        permissionBanner

                        statusAndTranscriptView
                            .frame(minHeight: isCompact ? 60 : 120, maxHeight: isCompact ? 120 : 200)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)

                bottomControls
                    .padding(.top, 8)
                    .padding(.bottom, isCompact ? 12 : 28)
            }
        }
        .onAppear {
            activeSessionId = sessionId
            dictation.keepsSessionActive = true
            configureAudioSession()
            startListening()
        }
        .onDisappear {
            stopAll()
            dictation.keepsSessionActive = false
            dictation.stop()
        }
        .onChange(of: phase) { _, new in
            AccessibilityNotification.Announcement(new.accessibilityName).post()
        }
        .onChange(of: voiceError) { _, new in
            if let new { AccessibilityNotification.Announcement(new).post() }
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Button {
                stopAll()
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Close voice mode")

            Spacer()

            HStack(spacing: 8) {
                AgentLogo(agent: currentAgentId, size: 22)
                Text(agentName)
                    .font(Theme.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
            .accessibilityElement(children: .combine)

            Spacer()

            // Balance the layout
            Color.clear
                .frame(width: 44, height: 44)
        }
    }

    private var bigAnimatedOrb: some View {
        let s = orbScale
        return Button {
            handleOrbTap()
        } label: {
            // Breathing is driven by time (no repeatForever animation fighting the level-driven spring).
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || phase == .listening)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let breath = (reduceMotion || phase == .listening) ? 0 : sin(t * 2.4) * 0.04
                orbLayers(scale: s, breath: breath)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Voice interaction orb")
        .accessibilityValue(phase.accessibilityName)
        .accessibilityHint(phase == .listening ? "Speak, or tap Send" : "Skips the spoken reply and listens again")
    }

    private func orbLayers(scale s: CGFloat, breath: Double) -> some View {
        let level = CGFloat(dictation.audioLevel)
        return ZStack {
            // Outer reactive ring
            Circle()
                .fill(
                    Theme.agentColor(currentAgentId)
                        .opacity(phase == .listening ? (0.12 + Double(level) * 0.45) : (phase == .speaking ? 0.22 : 0.08))
                )
                .frame(width: 240 * s, height: 240 * s)
                .scaleEffect(
                    (phase == .listening ? (1.0 + level * 0.5) : (phase == .speaking ? 1.08 : 1.0)) + CGFloat(breath)
                )
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.65), value: dictation.audioLevel)

            // Middle halo
            Circle()
                .fill(
                    Theme.agentColor(currentAgentId)
                        .opacity(phase == .listening ? (0.22 + Double(level) * 0.25) : 0.2)
                )
                .frame(width: 180 * s, height: 180 * s)
                .scaleEffect((phase == .listening ? (1.0 + level * 0.25) : 1.0) + CGFloat(breath) * 0.6)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.65), value: dictation.audioLevel)

            // Core orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.agentColor(currentAgentId).opacity(0.9),
                            Theme.accent.opacity(0.85),
                            Theme.surface
                        ],
                        center: .center,
                        startRadius: 15 * s,
                        endRadius: 75 * s
                    )
                )
                .frame(width: 140 * s, height: 140 * s)
                .shadow(color: Theme.accent.opacity(phase == .speaking ? 0.6 : 0.35), radius: 24 * s, x: 0, y: 0)

            SparkView(size: 72 * s, animating: !reduceMotion && (phase != .listening || dictation.audioLevel > 0.05))
        }
        .frame(width: 240 * s * 1.12, height: 240 * s * 1.12)
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if let request = pendingPermission, let sid = currentSessionId {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(Theme.accent)
                    Text("\(agentName) wants to use \(request.tool)")
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                }
                if let reason = request.reason, !reason.isEmpty {
                    Text(reason)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(3)
                }
                HStack(spacing: 10) {
                    Button {
                        store.answer(request, in: sid, allow: false)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text("Deny")
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.elevated, in: Capsule())
                    }
                    Button {
                        store.answer(request, in: sid, allow: true)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Text("Allow")
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.white, in: Capsule())
                    }
                }
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1))
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
        }
    }

    private var statusAndTranscriptView: some View {
        VStack(spacing: 12) {
            if let voiceError, phase == .listening {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                    Text(voiceError)
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                    Button {
                        startListening()
                    } label: {
                        Text("Try again")
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(Theme.elevated, in: Capsule())
                    }
                }
            } else {
                switch phase {
                case .listening:
                    if liveSpokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Listening\u{2026}")
                            .font(Theme.sans(17, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        autoScrollingText(liveSpokenText, font: Theme.sans(18, weight: .medium))
                    }

                case .thinking:
                    VStack(spacing: 10) {
                        WorkingDots()
                        Text("Thinking\u{2026}")
                            .font(Theme.sans(16, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    }

                case .speaking:
                    VStack(spacing: 8) {
                        autoScrollingText(agentReplyText, font: Theme.serif(18), lineSpacing: 4)
                        Text("Tap the orb to skip")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
        }
    }

    /// Text that keeps its newest line in view as it grows.
    private func autoScrollingText(_ text: String, font: Font, lineSpacing: CGFloat = 0) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Text(text)
                        .font(font)
                        .foregroundStyle(Theme.text)
                        .lineSpacing(lineSpacing)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Color.clear.frame(height: 1).id("voice-bottom")
                }
            }
            .onChange(of: text) { _, _ in
                proxy.scrollTo("voice-bottom", anchor: .bottom)
            }
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            if phase == .listening && !liveSpokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    commitAndSend()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                        Text("Send")
                            .font(Theme.sans(15, weight: .semibold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 48)
                    .background(Color.white, in: Capsule())
                }
                .transition(.scale.combined(with: .opacity))
            }

            if phase != .listening || isCommitting {
                Button {
                    stopAgent()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Stop agent")
                            .font(Theme.sans(15, weight: .semibold))
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 48)
                    .background(Theme.elevated, in: Capsule())
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(minHeight: 50)
        .animation(.smooth, value: liveSpokenText.isEmpty)
        .animation(.smooth, value: phase)
    }

    // MARK: - Actions & Conversation Flow

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startListening() {
        silenceTask?.cancel()
        speechCoordinator.stop()
        dictation.stop()

        phase = .listening
        liveSpokenText = ""
        voiceError = nil
        isCommitting = false

        dictation.start { spoken in
            guard self.phase == .listening else { return }
            self.liveSpokenText = spoken

            if !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.resetSilenceTimer()
            }
        } onError: { errorMsg in
            // The app-level toast sits beneath this full-screen cover, so show the problem here.
            self.voiceError = errorMsg
        }
    }

    private func resetSilenceTimer() {
        silenceTask?.cancel()
        silenceTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self.phase == .listening && !self.liveSpokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.commitAndSend()
                }
            }
        }
    }

    private func commitAndSend() {
        guard !isCommitting else { return }
        silenceTask?.cancel()
        dictation.stop()

        let trimmed = liveSpokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            startListening()
            return
        }

        isCommitting = true
        phase = .thinking
        agentReplyText = ""
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                let targetId: String
                let draftMode = UserDefaults.standard.string(forKey: "draftMode") ?? "agent"

                if let sid = currentSessionId {
                    targetId = sid
                } else if draftMode == "chat" {
                    let s = try await store.createChat(agent: ui.draftAgent, model: ui.draftModel)
                    adopt(s.id)
                    targetId = s.id
                } else {
                    let permMode = (ui.draftAgent == "claude") ? UserDefaults.standard.string(forKey: "draftPermissionMode") : nil
                    let model = store.agent(ui.draftAgent)?.model(ui.draftModel ?? store.agent(ui.draftAgent)?.defaultModel)
                    let effort = (model?.efforts?.isEmpty == false) ? ui.draftEffort : nil
                    let s = try await store.create(
                        agent: ui.draftAgent,
                        model: ui.draftModel,
                        effort: effort,
                        cwd: ui.draftProject,
                        permissionMode: permMode
                    )
                    adopt(s.id)
                    targetId = s.id
                }

                // Only a turn that appears after this point is the reply to this utterance.
                let t = store.transcript(for: targetId)
                let baseline = t.liveTurn?.id ?? t.lastAssistantTurn?.id
                store.send(trimmed, to: targetId, attachments: [])
                isCommitting = false
                monitorAgentReply(targetId: targetId, baselineTurnId: baseline)
            } catch {
                isCommitting = false
                startListening()
                voiceError = error.localizedDescription
            }
        }
    }

    /// Voice mode keeps working on the session it just created; the chat screen follows only if the user
    /// is still on the new-chat screen (ChatView subscribes then; otherwise subscribe here).
    private func adopt(_ newId: String) {
        activeSessionId = newId
        if ui.currentSessionId == nil {
            ui.openSession(newId)
        } else {
            store.open(newId)
        }
    }

    private func monitorAgentReply(targetId: String, baselineTurnId: String?) {
        monitorTask?.cancel()
        monitorTask = Task {
            let started = Date()
            var sawNewTurn = false
            var spokenOffset = 0
            var lastRaw = ""
            var lastCleaned = ""
            var failure: String?

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { break }

                let transcript = store.transcript(for: targetId)
                let working = transcript.isWorking

                var turn: AssistantTurn?
                if let live = transcript.liveTurn, live.id != baselineTurnId {
                    turn = live
                } else if !working, let last = transcript.lastAssistantTurn, last.id != baselineTurnId {
                    turn = last
                }

                if let turn {
                    sawNewTurn = true
                    let isDone = !working
                    let raw = turn.textBlocks.map(\.text).joined()
                    if raw != lastRaw {
                        lastRaw = raw
                        // While streaming, don't read past an unfinished "[link](" so the cleaned text only grows.
                        lastCleaned = VoiceSpeechCoordinator.cleanTextForSpeech(
                            isDone ? raw : VoiceSpeechCoordinator.stableSpeechPrefix(of: raw)
                        )
                    } else if isDone {
                        lastCleaned = VoiceSpeechCoordinator.cleanTextForSpeech(raw)
                    }

                    if !lastCleaned.isEmpty {
                        agentReplyText = lastCleaned
                        if phase == .thinking { phase = .speaking }
                    }

                    if lastCleaned.count > spokenOffset {
                        let unread = String(lastCleaned.dropFirst(spokenOffset))
                        if isDone {
                            spokenOffset = lastCleaned.count
                            await speechCoordinator.speakChunk(unread)
                        } else if let end = Self.sentenceBoundary(in: unread) {
                            spokenOffset += end
                            await speechCoordinator.speakChunk(String(unread.prefix(end)))
                        }
                    }
                }

                if sawNewTurn && !working { break }
                // The turn never showed up (dropped send / bridge down): give up instead of polling forever.
                if !sawNewTurn && !working && Date().timeIntervalSince(started) > 12 {
                    failure = "\(agentName) didn't reply. Check your connection and try again."
                    break
                }
            }

            guard !Task.isCancelled else { return }

            // Let the queued speech finish before listening again.
            await speechCoordinator.waitUntilFinished()
            guard !Task.isCancelled else { return }

            startListening()
            if let failure { voiceError = failure }
        }
    }

    /// End (exclusive character count) of the first complete sentence in `text`, or nil. Short replies like
    /// "Done." qualify; "3.5" and "e.g.x" don't because the delimiter must be followed by whitespace or the end.
    private static func sentenceBoundary(in text: String) -> Int? {
        let delimiters: Set<Character> = [".", "!", "?", "\n", "\u{061F}", "\u{3002}"]
        let chars = Array(text)
        for (idx, char) in chars.enumerated() where delimiters.contains(char) {
            let next = idx + 1
            if next == chars.count || chars[next].isWhitespace {
                return next
            }
        }
        return nil
    }

    private func handleOrbTap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch phase {
        case .speaking, .thinking:
            // Skip the speech only; the agent keeps working and its answer stays in the chat.
            monitorTask?.cancel()
            startListening()
        case .listening:
            if !liveSpokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commitAndSend()
            }
        }
    }

    private func stopAgent() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        monitorTask?.cancel()
        if let sid = currentSessionId {
            store.interrupt(sid)
        }
        startListening()
    }

    private func stopAll() {
        silenceTask?.cancel()
        monitorTask?.cancel()
        dictation.stop()
        speechCoordinator.stop()
    }
}

/// Natural voice coordinator using AVSpeechSynthesizer:
/// Picks the best available AVSpeechSynthesisVoice for the chosen language (premium/enhanced quality first),
/// cleans code blocks and linkup cards, and supports a streaming utterance queue.
@MainActor @Observable
final class VoiceSpeechCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var isSpeakingQueueActive = false
    @ObservationIgnored private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speakChunk(_ chunk: String) async {
        let cleaned = Self.cleanTextForSpeech(chunk)
        guard !cleaned.isEmpty else { return }

        isSpeakingQueueActive = true
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = cachedVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func waitUntilFinished() async {
        guard isSpeakingQueueActive || synthesizer.isSpeaking else { return }
        await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
        }
    }

    func stop() {
        isSpeakingQueueActive = false
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resumeWaiters()
    }

    private func resumeWaiters() {
        let waiting = pendingContinuations
        pendingContinuations.removeAll()
        for cont in waiting { cont.resume() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synthesizer.isSpeaking {
                self.isSpeakingQueueActive = false
                self.resumeWaiters()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeakingQueueActive = false
            self.resumeWaiters()
        }
    }

    private func cachedVoice() -> AVSpeechSynthesisVoice? {
        let key = LinkupSpeech.preferredIdentifier ?? "device"
        if let v = voiceCache[key] { return v }
        let v = Self.pickBestVoice()
        if let v { voiceCache[key] = v }
        return v
    }

    /// Selects the best natural voice for the chosen speech language (Settings value "linkupSpeechLanguage",
    /// falling back to the device language), premium/enhanced first.
    static func pickBestVoice() -> AVSpeechSynthesisVoice? {
        let wanted = (LinkupSpeech.preferredIdentifier
            ?? Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
        let lang = String(wanted.prefix(while: { $0 != "-" })).lowercased()
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let matching = allVoices.filter { $0.language.lowercased().hasPrefix(lang) }
        func exact(_ v: AVSpeechSynthesisVoice) -> Bool {
            v.language.replacingOccurrences(of: "_", with: "-").lowercased() == wanted.lowercased()
        }

        if let v = matching.first(where: { $0.quality == .premium && exact($0) }) { return v }
        if let v = matching.first(where: { $0.quality == .premium }) { return v }
        if let v = matching.first(where: { $0.quality == .enhanced && exact($0) }) { return v }
        if let v = matching.first(where: { $0.quality == .enhanced }) { return v }
        if let v = matching.first(where: { exact($0) }) { return v }
        if let v = matching.first { return v }
        return AVSpeechSynthesisVoice(language: wanted) ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    /// While a reply is streaming, drops a trailing unfinished "[label](url" so link syntax is never half-read.
    static func stableSpeechPrefix(of text: String) -> String {
        guard let open = text.lastIndex(of: "[") else { return text }
        let tail = text[open...]
        // A complete link "[x](y)" ends with ")" after "](".
        if let mid = tail.range(of: "]("), tail[mid.upperBound...].contains(")") { return text }
        if tail.contains("]") && !tail.contains("](") && !tail.hasSuffix("]") { return text }
        return String(text[..<open])
    }

    /// Strips code blocks, ```linkup-card blocks, and markdown symbols from speech text.
    static func cleanTextForSpeech(_ text: String) -> String {
        var lines: [String] = []
        var inCodeBlock = false
        var inCardBlock = false

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```linkup-card") {
                inCardBlock = true
                continue
            }
            if (inCardBlock || inCodeBlock) && trimmed.hasPrefix("```") {
                inCardBlock = false
                inCodeBlock = false
                continue
            }
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }

            if !inCodeBlock && !inCardBlock {
                lines.append(line)
            }
        }

        var cleaned = lines.joined(separator: "\n")

        // [Markdown links](url) -> label
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^\\)]+\\)") {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(location: 0, length: cleaned.utf16.count),
                withTemplate: "$1"
            )
        }

        // Clean common markdown characters
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")
        cleaned = cleaned.replacingOccurrences(of: "### ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "## ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "# ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "> ", with: "")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
