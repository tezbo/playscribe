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
    /// What UIKit actually gave the root view: its size and safe area. A pose is only reproduced when these equal the catalog.
    var viewSize = CGSize.zero
    var appliedInsets = UIEdgeInsets.zero
    var inheritedInsets = UIEdgeInsets.zero

    /// Nil when the root view has the pose's window size and safe area; otherwise the numbers, for the failure message.
    var geometryProblem: String? {
        func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.5 }
        let w = pose.windowSize, i = pose.safeArea, a = appliedInsets
        let ok = close(viewSize.width, w.width) && close(viewSize.height, w.height)
            && close(a.top, i.top) && close(a.left, i.left) && close(a.bottom, i.bottom) && close(a.right, i.right)
        return ok ? nil : "view \(viewSize) insets \(a) (window's own \(inheritedInsets)) but the pose needs \(w) and \(i)"
    }

    var division: CGRect? { pose.division }

    /// The same JSON the app prints for the simulator (`poseProbe`), for tools/qa/compare_harness.py.
    var probeJSON: String {
        var ctx = DuoReader<EmptyView>.context(size: pose.container, compact: pose.compactWidth,
                                               division: pose.division, occlusions: pose.occlusions)
        ctx.safeArea = EdgeInsets(top: appliedInsets.top, leading: appliedInsets.left,
                                  bottom: appliedInsets.bottom, trailing: appliedInsets.right)
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

    /// A control UIKit drew, found by accessibility identifier or label in the real view and accessibility tree (toolbar
    /// items are UIKit's, so this is where the system's own dropping of items shows). Frame in container coordinates.
    func uikitControl(identifier: String? = nil, label: String? = nil) -> CGRect? {
        func matches(_ o: NSObject) -> Bool {
            let id = (o as? UIAccessibilityIdentification)?.accessibilityIdentifier
            return (identifier != nil && id == identifier) || (label != nil && o.accessibilityLabel == label)
        }
        func frame(_ o: NSObject) -> CGRect? {
            if let v = o as? UIView {
                guard !v.isHidden, v.alpha > 0.01, v.window != nil else { return nil }
                return v.convert(v.bounds, to: window)
            }
            return window.convert(o.accessibilityFrame, from: window.screen.coordinateSpace)
        }
        func walk(_ o: NSObject, _ depth: Int) -> CGRect? {
            if depth > 40 { return nil }
            if matches(o), let f = frame(o), f.width > 1, f.height > 1, window.bounds.intersects(f) {
                return f.offsetBy(dx: -pose.safeArea.left, dy: -pose.safeArea.top)
            }
            var kids: [NSObject] = []
            if let v = o as? UIView { kids += v.subviews }
            kids += (o.accessibilityElements as? [NSObject]) ?? []
            let n = o.accessibilityElementCount()
            if n != NSNotFound, n > 0 { kids += (0..<min(n, 200)).compactMap { o.accessibilityElement(at: $0) as? NSObject } }
            for k in kids { if let f = walk(k, depth + 1) { return f } }
            return nil
        }
        return walk(window, 0)
    }

    /// What UIKit drew in the top 130 pt of the window, for failure messages (which classes, labels and frames).
    var topInventory: String {
        var out: [String] = []
        func walk(_ v: UIView, _ depth: Int) {
            guard depth < 30, !v.isHidden, v.alpha > 0.01 else { return }
            let f = v.convert(v.bounds, to: window)
            let name = String(describing: type(of: v))
            let interesting = v is UIControl || name.contains("Button") || v.accessibilityLabel != nil
            if interesting, f.minY < 130, f.width > 1, f.height > 1, out.count < 24 {
                out.append("\(name)[\(v.accessibilityLabel ?? "")|\((v as UIAccessibilityIdentification).accessibilityIdentifier ?? "")] \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))")
            }
            for s in v.subviews { walk(s, depth + 1) }
        }
        walk(window, 0)
        return out.joined(separator: "; ")
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
        hc.traitOverrides.horizontalSizeClass = pose.compactWidth ? .compact : .regular
        hc.traitOverrides.preferredContentSizeCategory = type
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: pose.windowSize)
        window.rootViewController = hc
        window.isHidden = false
        // The window inherits a safe area from the scene's real screen (the sim's own camera side), which would add to the
        // pose's. Lay out once with none added, read what was inherited, then add only the difference.
        window.layoutIfNeeded()
        hc.view.layoutIfNeeded()
        let inherited = hc.view.safeAreaInsets
        let t = pose.safeArea
        hc.additionalSafeAreaInsets = UIEdgeInsets(top: t.top - inherited.top, left: t.left - inherited.left,
                                                   bottom: t.bottom - inherited.bottom, right: t.right - inherited.right)
        for _ in 0..<4 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: settle / 4)
        }
        let origin = CGPoint(x: pose.safeArea.left, y: pose.safeArea.top)
        func rel(_ r: CGRect) -> CGRect { r.offsetBy(dx: -origin.x, dy: -origin.y) }
        var r = Rendered(pose: pose, livePose: model.livePose, frames: box.frames.map(rel),
                         named: box.named.mapValues(rel), window: window, controller: hc)
        r.viewSize = hc.view.bounds.size
        r.appliedInsets = hc.view.safeAreaInsets
        r.inheritedInsets = inherited
        return r
    }

    /// Tear down so the next pose starts clean.
    static func dispose(_ r: Rendered) {
        r.window.isHidden = true
        r.window.rootViewController = nil
    }
}
