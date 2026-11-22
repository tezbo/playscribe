import AVFoundation
import SwiftUI
import UIKit

// 6a, s-06-cover-trailer-loop: the Closed front cover's third motion mode. The game's official trailer loops, muted, behind the
// cover's shade, plate and lockup (CM-5: the shade belongs to the cover, so the caption keeps its contrast over any frame).
// Rights (12 Nov, restated on the card): the publisher's own mp4 plays from its source through AVPlayerLooper. Nothing is
// downloaded, re-hosted, trimmed, re-encoded or cached beyond the player's own buffer.

/// When the cover plays the loop, and what it shows instead. Pure, so the rules are unit tested.
enum TrailerLoopRule {
    /// The loop plays only when the person chose it, Reduce Motion is off, Autoplay videos is on (CM-1), the game has an
    /// official loop, Low Power Mode is off, and the source is https. Anything else shows Key-art motion, which keeps its own
    /// fallback to Still.
    static func plays(stored: CoverMotion, reduceMotion: Bool, autoplay: Bool, loop: URL?, lowPower: Bool) -> Bool {
        guard stored.resolved(reduceMotion: reduceMotion, autoplay: autoplay) == .trailer, !lowPower,
              let loop, loop.scheme?.lowercased() == "https" else { return false }
        return true
    }

    /// The loop URL for a game: the feed's `coverLoop`, or, in internal builds only, `-qaCoverLoop <https url>` for the first
    /// game on the cover (QA stills and the network log, before the feed carries one).
    static func url(for game: CatalogGame, lead: Bool) -> URL? {
        #if INTERNAL
        if lead, let qa = UserDefaults.standard.string(forKey: "qaCoverLoop"), let u = URL(string: qa) { return u }
        #endif
        return game.coverLoop.flatMap(URL.init(string:))
    }
}

/// The looping, muted trailer, filling its frame (aspect fill). It reports `ready` once the first frame can show, so the key
/// art stays in view until then and comes back if the source fails.
struct TrailerLoopArt: UIViewRepresentable {
    var url: URL
    var playing: Bool
    @Binding var ready: Bool

    func makeUIView(context: Context) -> LoopView {
        let view = LoopView()
        view.onReady = { ok in DispatchQueue.main.async { if ready != ok { ready = ok } } }
        view.load(url)
        view.setPlaying(playing)
        return view
    }

    func updateUIView(_ view: LoopView, context: Context) {
        if view.url != url { view.load(url) }
        view.setPlaying(playing)
    }

    static func dismantleUIView(_ view: LoopView, coordinator: ()) { view.stop() }

    final class LoopView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var statusObservation: NSKeyValueObservation?
        private var readyObservation: NSKeyValueObservation?
        private(set) var url: URL?
        var onReady: ((Bool) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func load(_ url: URL) {
            stop()
            self.url = url
            // Muted cover video must never stop the person's music: only when the app still has the default solo session.
            let session = AVAudioSession.sharedInstance()
            if session.category == .soloAmbient { try? session.setCategory(.ambient, options: .mixWithOthers) }
            let item = AVPlayerItem(url: url)
            // The player's own buffer only (the card's rights rule): a short forward buffer, no download task, no cache.
            item.preferredForwardBufferDuration = 8
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.allowsExternalPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: item)
            statusObservation = looper?.observe(\.status, options: [.new]) { [weak self] looper, _ in
                if looper.status == .failed { self?.onReady?(false) }
            }
            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                self?.onReady?(layer.isReadyForDisplay)
            }
            playerLayer.player = player
            self.player = player
        }

        func setPlaying(_ on: Bool) {
            guard let player else { return }
            if on, player.timeControlStatus == .paused { player.play() }
            if !on, player.timeControlStatus != .paused { player.pause() }
        }

        func stop() {
            statusObservation = nil
            readyObservation = nil
            looper?.disableLooping()
            player?.pause()
            player?.removeAllItems()
            playerLayer.player = nil
            looper = nil
            player = nil
        }
    }
}

/// The cover's art layer in Trailer loop mode: the key art (moving as Key-art motion while the loop loads or if it fails),
/// with the loop over it once its first frame is ready. Pauses with the app, off screen and under Low Power Mode.
struct TrailerLoopCoverArt<KeyArt: View>: View {
    var url: URL
    @ViewBuilder var keyArt: () -> KeyArt
    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false
    @State private var ready = false

    var body: some View {
        ZStack {
            keyArt()
            TrailerLoopArt(url: url, playing: onScreen && scenePhase == .active, ready: $ready)
                .opacity(ready ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: ready)
                .accessibilityHidden(true)
                .accessibilityIdentifier(ready ? "coverLoopPlaying" : "coverLoopLoading")
        }
        .clipped()
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
    }
}
