import AVFoundation
import Foundation

@MainActor
final class LiveAudioKeepAlive {
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private(set) var isPlaying = false
    private var startTime: Date?
    private var noTurnSince: Date?

    /// Setting toggle key "backgroundLiveMode" (UserDefaults, default true).
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "backgroundLiveMode") as? Bool ?? true
    }

    func start() {
        guard isEnabled, !isPlaying else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let audioEngine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            audioEngine.attach(player)

            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
                return
            }

            let frameCount: AVAudioFrameCount = 44100
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return
            }
            buffer.frameLength = frameCount

            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
            audioEngine.mainMixerNode.outputVolume = 0.0

            try audioEngine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            player.play()

            self.engine = audioEngine
            self.playerNode = player
            self.isPlaying = true
            self.startTime = Date()
            self.noTurnSince = nil
        } catch {
            stop()
        }
    }

    func stop() {
        guard isPlaying || engine != nil || playerNode != nil else { return }
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
        isPlaying = false
        startTime = nil
        noTurnSince = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Evaluates keep-alive rules when backgrounded:
    /// - Stop as soon as no turn is running for 10 s, or after 60 minutes.
    func tick(hasRunningTurn: Bool) {
        guard isPlaying else { return }

        // Hard cap: 60 minutes
        if let start = startTime, Date().timeIntervalSince(start) >= 3600 {
            stop()
            return
        }

        if hasRunningTurn {
            noTurnSince = nil
        } else {
            if let inactiveSince = noTurnSince {
                if Date().timeIntervalSince(inactiveSince) >= 10 {
                    stop()
                }
            } else {
                noTurnSince = Date()
            }
        }
    }
}
