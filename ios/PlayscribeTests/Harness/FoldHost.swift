import SwiftUI
import UIKit
@testable import Playscribe

/// What a rendered pose looked like, in container coordinates (the origin is the safe-area corner, as FoldAudit uses).
struct Rendered {
    var pose: HarnessPose
    var livePose: Pose
    var frames: [CGRect]
    var named: [String: CGRect]
    var window: UIWindow
    var controller: UIViewController

    var division: CGRect? { pose.division }

    /// The same JSON the app prints for the simulator (`poseProbe`), for tools/qa/compare_harness.py.
    var probeJSON: String {
        var ctx = DuoReader<EmptyView>.context(size: pose.container, compact: pose.compactWidth,
                                               division: pose.division, occlusions: pose.occlusions)
        ctx.safeArea = EdgeInsets(top: pose.safeArea.top, leading: pose.safeArea.left,
                                  bottom: pose.safeArea.bottom, trailing: pose.safeArea.right)
        return FoldAudit.probeJSON(frames: frames, duo: ctx, named: named, origin: .zero)
    }
    /// Frames that touch the active fold (the same test as FoldAudit).
    var foldCrossings: [CGRect] {
        guard let fold = division?.insetBy(dx: 0.5, dy: 0.5) else { return [] }
        return frames.filter { $0.width > 1 && $0.height > 1 && $0.intersects(fold) }
    }
    /// Tabletop: tappable frames that start above the fold (G-4).
    var aboveTheFold: [CGRect] {
        guard pose.expected == .tabletop, let fold = division else { return [] }
        return frames.filter { $0.width > 1 && $0.height > 1 && $0.minY < fold.minY }
    }

    /// A control UIKit drew, found by accessibility identifier or label in the real view tree (toolbar items are
    /// UIKit's, so this is the one place the system's own dropping of items shows). Frame in container coordinates.
    func uikitControl(identifier: String? = nil, label: String? = nil) -> CGRect? {
        func walk(_ v: UIView) -> CGRect? {
            if !v.isHidden, v.alpha > 0.01, v.window != nil {
                let hit = (identifier != nil && v.accessibilityIdentifier == identifier)
                    || (label != nil && v.accessibilityLabel == label)
                let r = v.convert(v.bounds, to: window)
                if hit, r.width > 1, r.height > 1, window.bounds.intersects(r) {
                    return r.offsetBy(dx: -pose.safeArea.left, dy: -pose.safeArea.top)
                }
            }
            for s in v.subviews { if let f = walk(s) { return f } }
            return nil
        }
        return walk(window)
    }
}

/// Renders the real RootView at a pose's exact container, with the fold supplied as reserved regions, in an offscreen
/// UIKit window, so UIKit (navigation bar, tab bar, size classes, Dynamic Type) lays it out as it does on the Duo.
@MainActor
enum FoldHost {
    final class Box { var frames: [CGRect] = []; var named: [String: CGRect] = [:] }

    struct Probe<Content: View>: View {
        var box: Box
        var content: Content
        var body: some View {
            content
                .onPreferenceChange(TappableFrameKey.self) { box.frames = $0 }
                .onPreferenceChange(NamedFrameKey.self) { box.named = $0 }
        }
    }

    static func demoModel() -> AppModel {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "fold-\(UUID().uuidString).json"))
        m.resetDemo()
        return m
    }

    /// `settle` covers the splash (about 1.1 s) and the first layout passes.
    static func render(_ pose: HarnessPose, type: UIContentSizeCategory = .large, model: AppModel = demoModel(),
                       settle: Duration = .milliseconds(1800)) async -> Rendered? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        FoldAuditSwitch.enabled = true
        let box = Box()
        let root = Probe(box: box, content: RootView()
            .environment(model)
            .environment(\.injectedRegions, pose.regions)
            .preferredColorScheme(.dark)
            .font(PlayscribeFont.body)
            .tint(PlayscribeColor.accent)
            .foregroundStyle(PlayscribeColor.textPrimary))
        let hc = UIHostingController(rootView: root)
        hc.additionalSafeAreaInsets = pose.safeArea
        hc.traitOverrides.horizontalSizeClass = pose.compactWidth ? .compact : .regular
        hc.traitOverrides.preferredContentSizeCategory = type
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0,
                              width: pose.container.width + pose.safeArea.left + pose.safeArea.right,
                              height: pose.container.height + pose.safeArea.top + pose.safeArea.bottom)
        window.rootViewController = hc
        window.isHidden = false
        for _ in 0..<4 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: settle / 4)
        }
        let origin = CGPoint(x: pose.safeArea.left, y: pose.safeArea.top)
        func rel(_ r: CGRect) -> CGRect { r.offsetBy(dx: -origin.x, dy: -origin.y) }
        return Rendered(pose: pose, livePose: model.livePose, frames: box.frames.map(rel),
                        named: box.named.mapValues(rel), window: window, controller: hc)
    }

    /// Tear down so the next pose starts clean.
    static func dispose(_ r: Rendered) {
        r.window.isHidden = true
        r.window.rootViewController = nil
    }
}
