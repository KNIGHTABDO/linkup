import SwiftUI
import AVFoundation
import Speech

enum VoiceModePhase {
    case listening
    case thinking
    case speaking
}

/// Full-screen voice conversation sheet:
/// - Listens with ComposerDictation, reacts to mic level RMS via animated orb.
/// - 1.5 s silence auto-send or manual "Send" tap.
/// - Streams agent response from transcript and speaks with natural AVSpeechSynthesizer voice (premium/enhanced).
/// - Skips code blocks and ```linkup-card blocks.
/// - Continuous conversation: listens again after speaking completes.
/// - Tapping the orb interrupts speaking.
struct VoiceModeView: View {
    let sessionId: String?
    @Binding var isPresented: Bool

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var activeSessionId: String? = nil
    @State private var phase: VoiceModePhase = .listening
    @State private var liveSpokenText: String = ""
    @State private var agentReplyText: String = ""
    @State private var dictation = ComposerDictation()
    @State private var speechCoordinator = VoiceSpeechCoordinator()

    @State private var silenceTask: Task<Void, Never>? = nil
    @State private var monitorTask: Task<Void, Never>? = nil

    private var currentAgentId: String {
        if let sid = activeSessionId ?? sessionId, let s = store.session(sid) {
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

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                Spacer()

                bigAnimatedOrb
                    .padding(.vertical, 30)

                statusAndTranscriptView
                    .frame(minHeight: 120, maxHeight: 180)
                    .padding(.horizontal, 24)

                Spacer()

                bottomControls
                    .padding(.bottom, 36)
            }
        }
        .onAppear {
            activeSessionId = sessionId
            configureAudioSession()
            startListening()
        }
        .onDisappear {
            stopAll()
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
                    .frame(width: 40, height: 40)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            HStack(spacing: 8) {
                AgentLogo(agent: currentAgentId, size: 22)
                Text(agentName)
                    .font(Theme.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))

            Spacer()

            // Balance the layout
            Color.clear
                .frame(width: 40, height: 40)
        }
    }

    private var bigAnimatedOrb: some View {
        Button {
            handleOrbTap()
        } label: {
            ZStack {
                // Outer pulsing reactive ring (reacts to mic level RMS)
                Circle()
                    .fill(
                        Theme.agentColor(currentAgentId)
                            .opacity(phase == .listening ? (0.12 + Double(dictation.audioLevel) * 0.45) : (phase == .speaking ? 0.22 : 0.08))
                    )
                    .frame(width: 240, height: 240)
                    .scaleEffect(
                        phase == .listening
                            ? (1.0 + CGFloat(dictation.audioLevel) * 0.5)
                            : (phase == .speaking ? 1.08 : 1.0)
                    )
                    .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.65), value: dictation.audioLevel)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: phase)

                // Middle halo
                Circle()
                    .fill(
                        Theme.agentColor(currentAgentId)
                            .opacity(phase == .listening ? (0.22 + Double(dictation.audioLevel) * 0.25) : 0.2)
                    )
                    .frame(width: 180, height: 180)
                    .scaleEffect(phase == .listening ? (1.0 + CGFloat(dictation.audioLevel) * 0.25) : 1.0)
                    .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.65), value: dictation.audioLevel)

                // Center core orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.agentColor(currentAgentId).opacity(0.9),
                                Theme.accent.opacity(0.85),
                                Theme.surface
                            ],
                            center: .center,
                            startRadius: 15,
                            endRadius: 75
                        )
                    )
                    .frame(width: 140, height: 140)
                    .shadow(color: Theme.accent.opacity(phase == .speaking ? 0.6 : 0.35), radius: 24, x: 0, y: 0)

                // SparkView inside the orb
                SparkView(size: 72, animating: phase != .listening || dictation.audioLevel > 0.05)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice interaction orb")
    }

    private var statusAndTranscriptView: some View {
        VStack(spacing: 12) {
            switch phase {
            case .listening:
                if liveSpokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Listening\u{2026}")
                        .font(Theme.sans(17, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ScrollView {
                        Text(liveSpokenText)
                            .font(Theme.sans(18, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
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
                    ScrollView {
                        Text(VoiceSpeechCoordinator.cleanTextForSpeech(agentReplyText))
                            .font(Theme.serif(18))
                            .foregroundStyle(Theme.text)
                            .lineSpacing(4)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    Text("Tap orb to interrupt")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
    }

    private var bottomControls: some View {
        HStack {
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
                    .padding(.vertical, 12)
                    .background(Circle().fill(Color.white).frame(height: 44), in: Capsule())
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 50)
        .animation(.smooth, value: liveSpokenText.isEmpty)
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

        phase = .listening
        liveSpokenText = ""

        dictation.start { spoken in
            guard self.phase == .listening else { return }
            self.liveSpokenText = spoken

            if !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.resetSilenceTimer()
            }
        } onError: { errorMsg in
            self.ui.toast = errorMsg
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
        silenceTask?.cancel()
        dictation.stop()

        let trimmed = liveSpokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            startListening()
            return
        }

        phase = .thinking
        agentReplyText = ""
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                let targetId: String
                let draftMode = UserDefaults.standard.string(forKey: "draftMode") ?? "agent"

                if let sid = activeSessionId {
                    targetId = sid
                } else if draftMode == "chat" {
                    let s = try await store.createChat(agent: ui.draftAgent, model: ui.draftModel)
                    ui.currentSessionId = s.id
                    store.open(s.id)
                    activeSessionId = s.id
                    targetId = s.id
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
                    activeSessionId = s.id
                    targetId = s.id
                }

                store.send(trimmed, to: targetId, attachments: [])
                monitorAgentReply(targetId: targetId)
            } catch {
                ui.toast = error.localizedDescription
                startListening()
            }
        }
    }

    private func monitorAgentReply(targetId: String) {
        monitorTask?.cancel()
        monitorTask = Task {
            var hasStartedSpeaking = false
            var spokenOffset = 0

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { break }

                let transcript = store.transcript(for: targetId)
                let turn = transcript.liveTurn ?? transcript.lastAssistantTurn

                if let turn {
                    let allText = turn.textBlocks.map(\.text).joined()
                    if !allText.isEmpty {
                        await MainActor.run {
                            self.agentReplyText = allText
                            if self.phase == .thinking {
                                self.phase = .speaking
                            }
                        }
                    }

                    // Speak completed sentences while streaming
                    let cleaned = VoiceSpeechCoordinator.cleanTextForSpeech(allText)
                    if cleaned.count > spokenOffset {
                        let unreadSlice = String(cleaned.dropFirst(spokenOffset))

                        let isDone = !transcript.isWorking && turn.finished != nil
                        if isDone {
                            // Speak entire remaining text
                            spokenOffset = cleaned.count
                            hasStartedSpeaking = true
                            await speechCoordinator.speakChunk(unreadSlice)
                            break
                        } else if let sentenceEnd = findSentenceBoundary(in: unreadSlice) {
                            let sentence = String(unreadSlice.prefix(sentenceEnd))
                            spokenOffset += sentenceEnd
                            hasStartedSpeaking = true
                            await speechCoordinator.speakChunk(sentence)
                        }
                    }
                }

                if !transcript.isWorking && turn?.finished != nil {
                    break
                }
            }

            // Wait until speech synthesis completely finishes
            await speechCoordinator.waitUntilFinished()

            guard !Task.isCancelled else { return }

            await MainActor.run {
                // Continuous conversation: listen again!
                self.startListening()
            }
        }
    }

    private func findSentenceBoundary(in text: String) -> Int? {
        let delimiters: [Character] = [".", "!", "?", "\n"]
        for (idx, char) in text.enumerated() {
            if delimiters.contains(char) && idx > 15 {
                let nextIdx = text.index(text.startIndex, offsetBy: idx + 1)
                if nextIdx == text.endIndex || text[nextIdx].isWhitespace {
                    return idx + 1
                }
            }
        }
        return nil
    }

    private func handleOrbTap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if phase == .speaking || phase == .thinking {
            // Interrupt speaking when user taps the orb
            monitorTask?.cancel()
            speechCoordinator.stop()
            if let sid = activeSessionId {
                store.interrupt(sid)
            }
            startListening()
        }
    }

    private func stopAll() {
        silenceTask?.cancel()
        monitorTask?.cancel()
        dictation.stop()
        speechCoordinator.stop()
    }
}

/// Natural voice coordinator using AVSpeechSynthesizer:
/// Picks the best available AVSpeechSynthesisVoice for the language (premium/enhanced quality first),
/// cleans code blocks and linkup cards, and supports streaming utterance queue.
@MainActor @Observable
final class VoiceSpeechCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    private var isSpeakingQueueActive = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speakChunk(_ chunk: String) async {
        let cleaned = Self.cleanTextForSpeech(chunk)
        guard !cleaned.isEmpty else { return }

        isSpeakingQueueActive = true
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = Self.pickBestVoice()
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
        for cont in pendingContinuations {
            cont.resume()
        }
        pendingContinuations.removeAll()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !synthesizer.isSpeaking {
                self.isSpeakingQueueActive = false
                for cont in self.pendingContinuations {
                    cont.resume()
                }
                self.pendingContinuations.removeAll()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeakingQueueActive = false
            for cont in self.pendingContinuations {
                cont.resume()
            }
            self.pendingContinuations.removeAll()
        }
    }

    /// Selects best natural voice for current language, premium/enhanced first.
    static func pickBestVoice() -> AVSpeechSynthesisVoice? {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let localeId = Locale.current.identifier
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let matching = allVoices.filter { $0.language.lowercased().hasPrefix(lang.lowercased()) }

        // 1. Premium matching exact locale
        if let v = matching.first(where: { $0.quality == .premium && $0.language == localeId }) {
            return v
        }
        // 2. Premium matching language prefix
        if let v = matching.first(where: { $0.quality == .premium }) {
            return v
        }
        // 3. Enhanced matching exact locale
        if let v = matching.first(where: { $0.quality == .enhanced && $0.language == localeId }) {
            return v
        }
        // 4. Enhanced matching language prefix
        if let v = matching.first(where: { $0.quality == .enhanced }) {
            return v
        }
        // 5. Default matching exact locale
        if let v = matching.first(where: { $0.language == localeId }) {
            return v
        }
        // 6. Any matching language
        if let v = matching.first {
            return v
        }
        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
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

        // Strip [Markdown links](url) -> Markdown links
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
