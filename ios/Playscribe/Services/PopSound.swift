import AVFoundation

/// A short pop when a game is added. Original CC0 sound made for Playscribe (brand/sound), bundled.
/// The ambient category follows the silent switch and mixes with the person's own audio, so it never
/// interrupts music or a call. Silent under Reduce Motion is not required: sound is not motion.
@MainActor
enum PopSound {
    private static var player: AVAudioPlayer? = {
        guard let url = Bundle.main.url(forResource: "playscribe-pop", withExtension: "caf") else { return nil }
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.volume = 0.6
        p?.prepareToPlay()
        return p
    }()

    /// One pop per batch, plus a quieter second one when more than 3 games land.
    /// Never plays while something else is playing, or in quiet hours.
    static func play(count: Int = 1, quiet: QuietHours? = nil) {
        let session = AVAudioSession.sharedInstance()
        if session.isOtherAudioPlaying || quiet?.contains(.now) == true { return }
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        player?.volume = 0.6
        player?.currentTime = 0
        player?.play()
        if count > 3 {
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                player?.volume = 0.3
                player?.currentTime = 0
                player?.play()
            }
        }
    }
}
