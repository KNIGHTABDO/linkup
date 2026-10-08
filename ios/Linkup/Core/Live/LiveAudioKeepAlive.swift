import AVFoundation
import Foundation

/// Plays inaudible audio so iOS keeps the app (and its WebSocket) alive while an agent works and the app is in the
/// background. Capped at 60 minutes per run of work; restarts after interruptions (calls, Siri) while a turn runs.
@MainActor
final class LiveAudioKeepAlive {
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private(set) var isPlaying = false
    /// When this run of work started the keep-alive. Survives restarts, so the 60-minute cap cannot be dodged.
    private var capStart: Date?
    private var noTurnSince: Date?
    /// The cap was reached: no restart until `reset()` (nothing running, or the app came back to the front).
    private(set) var hitCap = false
    private var interrupted = false
    private var observers: [NSObjectProtocol] = []

    /// True while the owner still wants audio (a turn is running and the app is in the background).
    var shouldRun: () -> Bool = { false }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in self?.interruption(rawType) }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.configurationChanged() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.configurationChanged() }
        })
    }

    /// Setting toggle key "backgroundLiveMode" (UserDefaults, default true).
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "backgroundLiveMode") as? Bool ?? true
    }

    func start() {
        guard isEnabled, !isPlaying, !hitCap else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let audioEngine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            audioEngine.attach(player)

            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
                deactivateSession()
                return
            }

            let frameCount: AVAudioFrameCount = 44100
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                deactivateSession()
                return
            }
            buffer.frameLength = frameCount

            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
            audioEngine.mainMixerNode.outputVolume = 0.0

            try audioEngine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            player.play()

            engine = audioEngine
            playerNode = player
            isPlaying = true
            interrupted = false
            if capStart == nil { capStart = Date() }
            noTurnSince = nil
        } catch {
            // iOS refused (e.g. started too late from the background): nothing is playing, so release the session.
            print("LiveAudioKeepAlive: could not start: \(error.localizedDescription)")
            engine?.stop()
            engine = nil
            playerNode = nil
            isPlaying = false
            deactivateSession()
        }
    }

    func stop() {
        guard isPlaying || engine != nil || playerNode != nil else { return }
        teardown()
        deactivateSession()
        noTurnSince = nil
    }

    /// The work is over (nothing running, or the app is in front): the next run gets a fresh 60 minutes.
    func reset() {
        capStart = nil
        hitCap = false
        noTurnSince = nil
        interrupted = false
    }

    /// Evaluates keep-alive rules when backgrounded:
    /// - Stop as soon as no turn is running for 10 s, or after 60 minutes (and then stay stopped).
    func tick(hasRunningTurn: Bool) {
        guard isPlaying else { return }

        if let start = capStart, Date().timeIntervalSince(start) >= 3600 {
            hitCap = true
            stop()
            return
        }

        if hasRunningTurn {
            noTurnSince = nil
        } else if let inactiveSince = noTurnSince {
            if Date().timeIntervalSince(inactiveSince) >= 10 { stop() }
        } else {
            noTurnSince = Date()
        }
    }

    // MARK: - Interruptions

    private func teardown() {
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
        isPlaying = false
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// A call, Siri or an alarm took the audio session: the engine is dead although `isPlaying` would say otherwise.
    private func interruption(_ rawType: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            if isPlaying {
                interrupted = true
                teardown()
            }
        case .ended:
            if interrupted {
                interrupted = false
                if shouldRun() { start() }
            }
        @unknown default:
            break
        }
    }

    /// Route change (headphones, Bluetooth) stopped the engine: bring it back if it is still wanted.
    private func configurationChanged() {
        guard isPlaying else { return }
        teardown()
        if shouldRun() { start() } else { deactivateSession() }
    }
}
