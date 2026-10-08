import Foundation
import Speech
import AVFoundation
import Observation

/// Speech language shared by dictation and voice mode (TTS + STT).
/// UserDefaults "linkupSpeechLanguage": "" = device language, otherwise "en-US" | "fr-FR" | "ar-MA" | "ar-SA".
enum LinkupSpeech {
    static let defaultsKey = "linkupSpeechLanguage"

    /// Normalised BCP-47 identifier ("fr_FR" -> "fr-FR"); nil = follow the device.
    static var preferredIdentifier: String? {
        let raw = (UserDefaults.standard.string(forKey: defaultsKey) ?? "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "_", with: "-")
        return raw.isEmpty ? nil : raw
    }

    /// Locale for speech recognition: the chosen language, falling back to a sibling region of the same language
    /// (ar-MA is not offered everywhere), then the device locale.
    static func recognizerLocale() -> Locale {
        let supported = SFSpeechRecognizer.supportedLocales()
        func has(_ id: String) -> Bool {
            supported.contains { $0.identifier.replacingOccurrences(of: "_", with: "-") == id }
        }
        if let id = preferredIdentifier {
            if has(id) { return Locale(identifier: id) }
            let lang = String(id.prefix(while: { $0 != "-" }))
            if let sibling = supported.first(where: { $0.language.languageCode?.identifier == lang }) {
                return sibling
            }
        }
        return Locale.current
    }

    /// Language code for choosing a TTS voice ("ar", "fr", "en"); nil = device language.
    static var voiceLanguage: String? {
        guard let id = preferredIdentifier else { return nil }
        return id
    }
}

/// Live speech-to-text into the composer using SFSpeechRecognizer + AVAudioEngine.
@MainActor @Observable
final class ComposerDictation {
    var isListening: Bool = false
    var audioLevel: Float = 0.0

    /// Voice mode owns the audio session (it also speaks); dictation must not deactivate it on stop.
    @ObservationIgnored var keepsSessionActive = false

    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    /// Bumped on every start/stop so a late permission result or recognition callback can't revive a stopped run.
    @ObservationIgnored private var generation = 0

    init() {}

    func start(onUpdate: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        // Synchronous: a second tap while permissions are pending can't start a second engine.
        guard !isListening else { return }
        teardown(deactivate: false)
        generation += 1
        let gen = generation
        isListening = true

        Task {
            let authorized = await Self.requestPermissions()
            guard gen == generation, isListening else { return }
            guard authorized else {
                stop()
                onError("Allow Microphone and Speech Recognition for Linkup in Settings to dictate.")
                return
            }
            do {
                try beginRecording(gen: gen, onUpdate: onUpdate, onError: onError)
            } catch {
                stop()
                onError(error.localizedDescription)
            }
        }
    }

    func stop() {
        generation += 1
        isListening = false
        teardown(deactivate: true)
    }

    private func teardown(deactivate: Bool) {
        audioLevel = 0.0
        if let engine = audioEngine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if deactivate && !keepsSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func beginRecording(gen: Int, onUpdate: @escaping (String) -> Void,
                                onError: @escaping (String) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        // playAndRecord (not record) so speech output keeps working; duckOthers is invalid for dictation anyway.
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let locale = LinkupSpeech.recognizerLocale()
        let rec = (recognizer?.locale.identifier == locale.identifier ? recognizer : nil)
            ?? SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer()
        recognizer = rec
        guard let rec, rec.isAvailable else {
            throw NSError(domain: "ComposerDictation", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Speech recognition isn't available for this language right now."
            ])
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        recognitionRequest = request

        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format,
                         block: Self.makeTap(request: request) { [weak self] level in
            Task { @MainActor [weak self] in self?.audioLevel = level }
        })
        engine.prepare()
        try engine.start()

        recognitionTask = Self.makeTask(recognizer: rec, request: request) { [weak self] text, errorCode, errorText in
            Task { @MainActor [weak self] in
                guard let self, gen == self.generation, self.isListening else { return }
                if let text { onUpdate(text) }
                if let errorCode {
                    // 1110 = "no speech detected": end quietly. Anything else before any text is worth showing.
                    let silent = errorCode == 1110 || errorCode == 216 || errorCode == 301
                    self.stop()
                    if !silent, let errorText { onError(errorText) }
                }
            }
        }
    }

    // MARK: Off-actor helpers (audio / Speech callbacks fire on their own queues)

    nonisolated private static func makeTap(request: SFSpeechAudioBufferRecognitionRequest,
                                            level: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            request.append(buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += channel[i] * channel[i] }
            let rms = (sum / Float(n)).squareRoot()
            level(min(max(rms * 8.0, 0.0), 1.0))
        }
    }

    nonisolated private static func makeTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, Int?, String?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let ns = error as NSError?
            handler(text, ns?.code, ns?.localizedDescription)
        }
    }

    nonisolated private static func requestPermissions() async -> Bool {
        let speechGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
