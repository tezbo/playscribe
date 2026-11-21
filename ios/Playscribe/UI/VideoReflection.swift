import SwiftUI
import UIKit
import WebKit

/// Reflection mode (R-11; Terry's Duo test, 14 Nov, 0.5.5; redrawn to Iris's reflection-0.6 spec after Terry's Duo, 21 Nov: "not a
/// very elegant solution"). In Tabletop only, the playing video stands on the fold like an object on a table and the lower half
/// shows a reflection of its base: the video's bottom strip, at true scale, flipped, softly blurred and fading to the surface.
/// The mirror is the render server's replica of the playing web view (see `VideoMirrorStrip`), so it is the live picture. No
/// poster or held frame stands in for it. When there is no live picture to mirror (before playback starts, under Reduce Motion
/// or Reduce Transparency, the setting off, or any pose but Tabletop) there is no mirror at all. View only: it takes no touches.
enum VideoReflection {
    static let key = "reflectionMode"
    /// On unless the person turns it off (Terry, 2026-11-06). The Settings toggle reads the same value.
    static let defaultOn = true

    /// The band: at most 120 pt and never more than 15% of the lower half (the Tabletop edge-band cap). The strip mirrored is
    /// the same height, so the reflection is at true scale (spec 4: the quarter squash of 0.5.6 to 0.5.9 read as a smear and
    /// flipped the subtitles into view).
    static let height: CGFloat = 120
    static let maxShare: CGFloat = 0.15

    /// The band for a lower half this tall.
    static func band(lowerHalf: CGFloat) -> CGFloat { max(0, min(height, lowerHalf * maxShare)) }

    /// Strength at the video's base: 35% while the controls are hidden, 20% while they show, so white text over a mirrored white
    /// frame keeps 12:1, and the grey 4.5:1, with no plates (spec 4, contrast worked out).
    static let edgeHidden = 0.35
    static let edgeShown = 0.20
    static func edgeOpacity(controlsShown: Bool) -> Double { controlsShown ? edgeShown : edgeHidden }

    /// Gaussian blur on the replica, in points (spec 4). Applied by SwiftUI to the strip alone, never to the video.
    static let blur: CGFloat = 3

    /// The fade down the band, 0 at the video's base to 1 at the band's end: quadratic ease-out, (1 - t)^2, reaching zero at the
    /// end with no step (spec 8.2).
    static func fade(_ t: Double) -> Double { let c = min(1, max(0, t)); return (1 - c) * (1 - c) }

    /// The fade as a mask: eleven stops sampled from `fade`, so each step between stops is at most 0.19 of the edge strength
    /// (under 4/255 at 35%) and the gradient interpolates in between.
    static var fadeMask: LinearGradient {
        LinearGradient(stops: (0...10).map { i in
            let t = Double(i) / 10
            return Gradient.Stop(color: .white.opacity(fade(t)), location: t)
        }, startPoint: .top, endPoint: .bottom)
    }

    /// True when the mirror shows: Tabletop, the setting on, Reduce Transparency off, and Reduce Motion off (a live mirror
    /// moves; G-9). There is no still mirror.
    static func shows(pose: Pose, setting: Bool, reduceMotion: Bool, reduceTransparency: Bool) -> Bool {
        pose == .tabletop && setting && !reduceMotion && !reduceTransparency
    }

    /// Where the replica sits inside a strip `band` tall, before the strip is flipped: its bottom row on the strip's bottom edge,
    /// so after the flip the video's last row is the strip's first (spec 8.1, continuity) and only the bottom `band` rows show.
    static func replicaFrame(video: CGSize, band: CGFloat) -> CGRect {
        CGRect(x: 0, y: band - video.height, width: video.width, height: video.height)
    }

    /// True when the strip is drawing a mirror a person can see: a replica with height, on screen. The audit reports this, not
    /// the intent (Mac at 95d9f3b: the audit said on while the band was blank).
    static func rendering(hasReplica: Bool, band: CGFloat, onScreen: Bool) -> Bool {
        hasReplica && band > 0 && onScreen
    }

    /// Replicas per second. The spec asks for 15 at least and 30 if the Duo's CPU and heat allow: the link asks for 30 and the
    /// system may drop to 15 (measure on the Duo).
    static let frameRate = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
}

/// The player's web view on the stage. One web view lives for the whole presentation and moves between poses (P-2), so the
/// surface takes it back if another surface held it.
struct VideoSurface: UIViewRepresentable {
    var webView: WKWebView

    final class Host: UIView {
        weak var video: UIView?
        override func layoutSubviews() { super.layoutSubviews(); video?.frame = bounds }
    }

    func makeUIView(context: Context) -> Host {
        let host = Host()
        host.backgroundColor = .clear
        host.addSubview(webView)
        host.video = webView
        return host
    }

    func updateUIView(_ host: Host, context: Context) {
        if webView.superview !== host { host.addSubview(webView); host.video = webView; host.setNeedsLayout() }
    }

    static func dismantleUIView(_ host: Host, coordinator: ()) {
        // Only if it is still here: the next pose's surface may already have taken it.
        if host.video?.superview === host { host.video?.removeFromSuperview() }
    }
}

/// The reflection (R-11): the bottom `band` rows of the playing web view, at 1:1, flipped so the video's last row comes first.
/// The caller sizes it to the video's width and the band, and applies the blur, the fade mask and the edge strength in SwiftUI.
///
/// The copy is the render server's own replica of the web view (`snapshotView(afterScreenUpdates: false)`), refreshed up to 30
/// times a second while it is on screen, so it is the live picture, never a poster or a still. A `CAReplicatorLayer` drew on the
/// simulator but not on Terry's Duo (19 Nov), where WebKit's video is a hosted layer; a replica view is drawn by the render server
/// from what is on screen, hosted video included. The crop is a clip, so it costs nothing beyond the replica itself.
struct VideoMirrorStrip: UIViewRepresentable {
    var source: WKWebView
    var band: CGFloat
    /// Called with what is actually drawn (`VideoReflection.rendering`), whenever that changes. For the QA audit.
    var report: (Bool) -> Void = { _ in }

    final class Host: UIView {
        weak var source: UIView?
        var report: (Bool) -> Void = { _ in }
        /// Flipped top to bottom; holds the replica.
        private let flip = UIView()
        private var link: CADisplayLink?
        private var reported: Bool?

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            flip.isUserInteractionEnabled = false
            addSubview(flip)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            flip.transform = .identity
            flip.frame = bounds
            flip.transform = CGAffineTransform(scaleX: 1, y: -1)
            if let size = source?.bounds.size {
                for v in flip.subviews { v.frame = VideoReflection.replicaFrame(video: size, band: bounds.height) }
            }
            publish()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil, link == nil {
                let l = CADisplayLink(target: self, selector: #selector(refresh))
                l.preferredFrameRateRange = VideoReflection.frameRate
                l.add(to: .main, forMode: .common)
                link = l
            } else if window == nil {
                link?.invalidate(); link = nil
                flip.subviews.forEach { $0.removeFromSuperview() }
            }
            publish()
        }

        @objc private func refresh() {
            guard let source, source.window != nil, bounds.height > 0,
                  let copy = source.snapshotView(afterScreenUpdates: false) else {
                // No replica this frame: clear the mirror rather than hold the last frame (Quinn on #550).
                if !flip.subviews.isEmpty { flip.subviews.forEach { $0.removeFromSuperview() }; publish() }
                return
            }
            copy.isUserInteractionEnabled = false
            copy.frame = VideoReflection.replicaFrame(video: source.bounds.size, band: bounds.height)
            let old = flip.subviews
            flip.addSubview(copy)
            old.forEach { $0.removeFromSuperview() }
            publish()
        }

        private func publish() {
            let now = VideoReflection.rendering(hasReplica: !flip.subviews.isEmpty, band: bounds.height, onScreen: window != nil)
            guard now != reported else { return }
            reported = now
            let report = report
            // Out of the layout pass: the callback writes SwiftUI state.
            DispatchQueue.main.async { report(now) }
        }

        override func removeFromSuperview() {
            link?.invalidate(); link = nil
            super.removeFromSuperview()
        }
    }

    func makeUIView(context: Context) -> Host {
        let host = Host()
        host.source = source
        host.report = report
        return host
    }

    func updateUIView(_ host: Host, context: Context) {
        host.source = source
        host.report = report
        host.setNeedsLayout()
    }

    static func dismantleUIView(_ host: Host, coordinator: ()) {
        let report = host.report
        DispatchQueue.main.async { report(false) }
    }
}

/// QA (INTERNAL builds only): the mirror's state as an accessibility label ("mirror: on" or "mirror: off"), so a UI test reads it
/// in any pose. A screenshot cannot: it shows only one display, and video pixels are not readable on the simulator.
struct MirrorAudit: View {
    var on: Bool
    /// Where the video and the mirror band sit, in window points, for a UI test that measures the band's pixels (R-11, 19 Nov:
    /// the label alone said on while Terry's Duo showed no visible mirror). "video x y w h band top height", or empty.
    var geometry: String = ""
    var body: some View {
        #if INTERNAL
        Text("mirror")
            .font(.system(size: 1))
            .opacity(0.01)
            .accessibilityIdentifier("mirrorAudit")
            .accessibilityLabel("mirror: \(on ? "on" : "off")")
            .accessibilityValue(geometry)
            .allowsHitTesting(false)
        #endif
    }
}

extension MirrorAudit {
    /// The audit's geometry string: the video frame and the band, rounded to whole points.
    static func geometry(video v: CGRect, bandTop: CGFloat, band: CGFloat) -> String {
        [v.minX, v.minY, v.width, v.height, bandTop, band].map { String(Int($0.rounded())) }.joined(separator: " ")
    }
}
