import Foundation
import Speech
import AVFoundation
import Observation

/// Live speech-to-text into the composer using SFSpeechRecognizer + AVAudioEngine.
@MainActor @Observable
final class ComposerDictation {
    var isListening: Bool = false

    @ObservationIgnored private var speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var audioEngine: AVAudioEngine?

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    func start(onUpdate: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        if isListening {
            stop()
        }

        Task {
            let authorized = await requestPermissions()
            guard authorized else {
                onError("Microphone or speech recognition permission denied")
                return
            }

            do {
                try beginRecording(onUpdate: onUpdate, onError: onError)
            } catch {
                stop()
                onError(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard isListening || audioEngine != nil || recognitionTask != nil else { return }
        isListening = false

        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginRecording(onUpdate: @escaping (String) -> Void, onError: @escaping (String) -> Void) throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let recognizer = speechRecognizer ?? SFSpeechRecognizer(locale: Locale.current)
        speechRecognizer = recognizer
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(
                domain: "ComposerDictation",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition is not available right now"]
            )
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                if let result {
                    let transcribed = result.bestTranscription.formattedString
                    onUpdate(transcribed)
                }
                if error != nil {
                    self.stop()
                }
            }
        }
    }

    private func requestPermissions() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else { return false }

        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        return micGranted
    }
}
