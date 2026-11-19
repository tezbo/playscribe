import SwiftUI
import UIKit
import WebKit

/// Reflection mode (R-11; Terry's Duo test, 14 Nov, 0.5.5): in Tabletop only, the playing video is mirrored under the fold,
/// behind the lower-half controls. The system compositor draws the mirror: the video's web view sits in a `CAReplicatorLayer`
/// whose second instance is the same layer tree flipped and moved below the fold, so the mirror is the live picture itself,
/// frame for frame. Nothing is snapshotted and no still stands in for it (the poster mirror of 0.5.4 read as a fake). When
/// there is no live picture to mirror (before playback starts, under Reduce Motion or Reduce Transparency, the setting off,
/// or any pose but Tabletop) there is no mirror at all. View only: replicated instances take no touches (Tabletop rule).
enum VideoReflection {
    static let key = "reflectionMode"
    /// On unless the person turns it off (Terry, 2026-11-06). The Settings toggle reads the same value.
    static let defaultOn = true

    /// Strength at the video's bottom edge, at most 30%, and the band it fades out over: at most 120 pt and never more than 15%
    /// of the lower half, the Tabletop edge-band cap (Iris on #533, 14 Nov: the 60%, 120 pt mirror was 20% of the half and the
    /// player's own chrome read upside down in it).
    static let opacity = 0.3
    static let height: CGFloat = 120
    static let maxShare: CGFloat = 0.15

    /// The band for a lower half this tall.
    static func band(lowerHalf: CGFloat) -> CGFloat { max(0, min(height, lowerHalf * maxShare)) }

    /// True when the mirror shows: Tabletop, the setting on, Reduce Transparency off, and Reduce Motion off (a live mirror
    /// moves; G-9). There is no still mirror any more.
    static func shows(pose: Pose, setting: Bool, reduceMotion: Bool, reduceTransparency: Bool) -> Bool {
        pose == .tabletop && setting && !reduceMotion && !reduceTransparency
    }

    /// The mirror is squashed to a quarter of the video's height, so text in the picture (the player's own chrome, captions, an age
    /// rating) is flattened past reading while its light and colour still move with the video. This stands in for a blur: the
    /// system's only backdrop blur (a material) lifts black to grey and buried the mirror entirely (Mac at 95d9f3b: the band read
    /// the same 20 of 255 with the video changing), and no public API blurs one replicator instance.
    static let squash: CGFloat = 0.25

    /// The second instance's transform, in the replicator's own space (about its centre): flipped top to bottom and squashed by
    /// `squash`, then moved down so the video's bottom row lands `gap` below the video's bottom edge (at the top of the lower half
    /// in Tabletop). A point at y maps to `h + gap + squash * (h - y)`.
    static func instanceTransform(videoHeight h: CGFloat, gap: CGFloat, squash s: CGFloat = squash) -> CATransform3D {
        CATransform3DConcat(CATransform3DMakeScale(1, -s, 1), CATransform3DMakeTranslation(0, h * (1 + s) / 2 + gap, 0))
    }

    /// True when the replicator is drawing a mirror a person can see: two instances, a picture with height, a second instance with
    /// some alpha, on screen. The audit reports this, not the intent (Mac at 95d9f3b: the audit said on while the band was blank).
    static func rendering(instanceCount: Int, height: CGFloat, mirrorAlpha: Float, onScreen: Bool) -> Bool {
        instanceCount >= 2 && height > 0 && mirrorAlpha > 0.05 && onScreen
    }
}

/// The player's web view, hosted in a `CAReplicatorLayer` (R-11). `mirrored` adds the flipped second instance at
/// `VideoReflection.opacity`; off, it is the plain web view. The mirror draws outside this view's frame, from `gap` below its
/// bottom edge; the caller lays the fade over it.
struct MirroredVideoSurface: UIViewRepresentable {
    var webView: WKWebView
    var mirrored: Bool
    var gap: CGFloat = 0
    /// Called with what the layer is actually drawing (`VideoReflection.rendering`), whenever that changes. For the QA audit.
    var report: (Bool) -> Void = { _ in }

    final class Host: UIView {
        override class var layerClass: AnyClass { CAReplicatorLayer.self }
        var mirrored = false { didSet { if mirrored != oldValue { setNeedsLayout() } } }
        var gap: CGFloat = 0 { didSet { if gap != oldValue { setNeedsLayout() } } }
        var report: (Bool) -> Void = { _ in }
        private var reported: Bool?

        override func layoutSubviews() {
            super.layoutSubviews()
            for v in subviews { v.frame = bounds }
            guard let r = layer as? CAReplicatorLayer else { return }
            r.masksToBounds = false
            r.instanceCount = mirrored ? 2 : 1
            r.instanceTransform = VideoReflection.instanceTransform(videoHeight: bounds.height, gap: gap)
            r.instanceAlphaOffset = Float(VideoReflection.opacity - 1)
            publish()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            setNeedsLayout()
            publish()
        }

        private func publish() {
            guard let r = layer as? CAReplicatorLayer else { return }
            let now = VideoReflection.rendering(instanceCount: r.instanceCount, height: bounds.height,
                                                mirrorAlpha: 1 + r.instanceAlphaOffset, onScreen: window != nil && !subviews.isEmpty)
            guard now != reported else { return }
            reported = now
            let report = report
            // Out of the layout pass: the callback writes SwiftUI state.
            DispatchQueue.main.async { report(now) }
        }
    }

    func makeUIView(context: Context) -> Host {
        let host = Host()
        host.clipsToBounds = false
        host.backgroundColor = .clear
        host.addSubview(webView)
        return host
    }

    func updateUIView(_ host: Host, context: Context) {
        // The one web view moves between poses (P-2): take it back if another surface held it.
        if webView.superview !== host { host.addSubview(webView); host.setNeedsLayout() }
        host.report = report
        host.mirrored = mirrored
        host.gap = gap
    }

    static func dismantleUIView(_ host: Host, coordinator: ()) {
        // Only if it is still here: the next pose's surface may already have taken it.
        for v in host.subviews { v.removeFromSuperview() }
    }
}

/// Over the mirror (R-11): a fade that is clear for the first 35% of the band and the page's black at its end, and black below,
/// so only the squashed picture's light shows, strongest at the edge. No material: it lifts black to grey (Mac at 95d9f3b).
/// Takes no touches; hidden from VoiceOver.
struct MirrorFade: View {
    var band: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black.opacity(0), location: 0.35),
                                   .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: band)
            Color.black
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Text that sits over the mirror (R-11, Max and Iris, 12 Nov): a soft-edged black plate at 88% behind it, so grey text keeps
    /// 4.5:1 on any frame, bright ones included. The plate adds no layout room and takes no touches.
    @ViewBuilder func overMirror(_ on: Bool) -> some View {
        if on {
            background {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.88))
                    // A dense core under the glyphs and a long feathered edge: the margin is twice the blur, so the text sits in
                    // the full-strength core and the fall-off happens outside it; the trailing side runs 48 pt past the text before
                    // it feathers, where the subtitle's last glyphs fell to 3.3:1 (Iris, 12 Nov) (Iris, 12 Nov: no hard box, no outline).
                    .padding(EdgeInsets(top: -30, leading: -30, bottom: -30, trailing: -63)).blur(radius: 15).allowsHitTesting(false)
            }
        } else { self }
    }
}

/// QA (INTERNAL builds only): the mirror's state as an accessibility label ("mirror: on" or "mirror: off"), so a UI test reads it
/// in any pose. A screenshot cannot: it shows only one display, and video pixels are not readable on the simulator.
struct MirrorAudit: View {
    var on: Bool
    var body: some View {
        #if INTERNAL
        Text("mirror")
            .font(.system(size: 1))
            .opacity(0.01)
            .accessibilityIdentifier("mirrorAudit")
            .accessibilityLabel("mirror: \(on ? "on" : "off")")
            .allowsHitTesting(false)
        #endif
    }
}
