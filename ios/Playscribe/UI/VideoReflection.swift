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

    /// Strength at the video's bottom edge, and the band it fades out over (Iris and Quinn, 12 Nov).
    static let opacity = 0.6
    static let height: CGFloat = 120

    /// True when the mirror shows: Tabletop, the setting on, Reduce Transparency off, and Reduce Motion off (a live mirror
    /// moves; G-9). There is no still mirror any more.
    static func shows(pose: Pose, setting: Bool, reduceMotion: Bool, reduceTransparency: Bool) -> Bool {
        pose == .tabletop && setting && !reduceMotion && !reduceTransparency
    }

    /// The second instance's transform, in the replicator's own space (about its centre): flipped top to bottom, then moved
    /// down so the video's bottom row lands `gap` below the video's bottom edge (at the top of the lower half in Tabletop).
    /// A point at y maps to `2 * height + gap - y`.
    static func instanceTransform(videoHeight h: CGFloat, gap: CGFloat) -> CATransform3D {
        CATransform3DConcat(CATransform3DMakeScale(1, -1, 1), CATransform3DMakeTranslation(0, h + gap, 0))
    }
}

/// The player's web view, hosted in a `CAReplicatorLayer` (R-11). `mirrored` adds the flipped second instance at
/// `VideoReflection.opacity`; off, it is the plain web view. The mirror draws outside this view's frame, from `gap` below its
/// bottom edge; the caller lays the fade over it.
struct MirroredVideoSurface: UIViewRepresentable {
    var webView: WKWebView
    var mirrored: Bool
    var gap: CGFloat = 0

    final class Host: UIView {
        override class var layerClass: AnyClass { CAReplicatorLayer.self }
        var mirrored = false { didSet { if mirrored != oldValue { setNeedsLayout() } } }
        var gap: CGFloat = 0 { didSet { if gap != oldValue { setNeedsLayout() } } }

        override func layoutSubviews() {
            super.layoutSubviews()
            for v in subviews { v.frame = bounds }
            guard let r = layer as? CAReplicatorLayer else { return }
            r.masksToBounds = false
            r.instanceCount = mirrored ? 2 : 1
            r.instanceTransform = VideoReflection.instanceTransform(videoHeight: bounds.height, gap: gap)
            r.instanceAlphaOffset = Float(VideoReflection.opacity - 1)
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
        host.mirrored = mirrored
        host.gap = gap
    }

    static func dismantleUIView(_ host: Host, coordinator: ()) {
        // Only if it is still here: the next pose's surface may already have taken it.
        for v in host.subviews { v.removeFromSuperview() }
    }
}

/// The fade over the mirror (R-11): clear for the first 35% of the band, then to the page's black at 120 pt, and black
/// below, so only the video's last rows show, strongest at the edge. Takes no touches.
struct MirrorFade: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black.opacity(0), location: 0.35),
                                   .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: VideoReflection.height)
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
