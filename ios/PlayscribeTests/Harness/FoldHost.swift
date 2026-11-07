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
    /// Whether the layout stopped changing before the time cap (the frames the app reports were identical for three passes in a
    /// row), and how many passes that took. A feedback loop in layout (#292) shows here as `settled == false`.
    var settled = true
    var passes = 0
    var viewSize = CGSize.zero
    var appliedInsets = UIEdgeInsets.zero
    var inheritedInsets = UIEdgeInsets.zero

    /// Nil when the root view has the pose's window size and safe area; otherwise the numbers, for the failure message.
    var geometryProblem: String? {
        func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.5 }
        let w = pose.windowSize, a = appliedInsets
        var i = pose.safeArea
        if pose.tabBarSuppliesTrailingInset { i.right = 0 }
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
                                  bottom: appliedInsets.bottom, trailing: pose.tabBarSuppliesTrailingInset ? pose.safeArea.right : appliedInsets.right)
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
        return frames.filter { $0.width > 1 && $0.height > 1 && $0.minY < fold.minY && !inNavigationBand($0) }
    }

    /// Hosted offscreen, the system navigation bar puts SwiftUI toolbar content in the top band (CI saw a 220 x 44 frame there in
    /// Tabletop; the real Duo, in the Mac calibration, has none). The bar is the system's, not the app's stage, so it belongs to
    /// the real-hinge gate (TB-1, like the toolbar itself) and is reported, not asserted.
    func inNavigationBand(_ f: CGRect) -> Bool { f.maxY <= 60 }
    var navigationBandFrames: [CGRect] { frames.filter { $0.width > 1 && $0.height > 1 && inNavigationBand($0) } }

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
            let name = String(describing: Swift.type(of: v))
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
                       settle: Duration = .milliseconds(1800), insetAdjust: UIEdgeInsets = .zero) async -> Rendered? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        // Dates are formatted in the device's time zone, so a patch near midnight UTC reads 25 Jun on a UTC runner and 26 Jun on
        // the AEDT Mac (Quinn, KCD II 1.5.6). Pin the harness to the Mac's zone so stills compare with the Mac's.
        NSTimeZone.default = TimeZone(identifier: "Australia/Sydney") ?? .current
        FoldAuditSwitch.enabled = true
        let box = Box()
        let root = Probe(box: box, content: RootView()
            .environment(model)
            .environment(\.injectedRegions, pose.regions)
            .environment(\.harnessSplit, ProcessInfo.processInfo.environment["HARNESS_SPLIT"] == "1")
            .preferredColorScheme(.dark)
            .font(PlayscribeFont.body)
            .tint(PlayscribeColor.accent)
            .foregroundStyle(PlayscribeColor.textPrimary))
        let hc = UIHostingController(rootView: root)
        hc.traitOverrides.horizontalSizeClass = pose.compactWidth ? .compact : .regular
        // The hosting window is a small square, so UIKit gave the tab view a compact vertical size class and drew its tab bar
        // as a vertical bar down the trailing edge (CI view tree: VerticalBarPocketView 83 pt wide, content safe area right 172
        // = 84 + 88), where the Duo draws it along the bottom. That one trait is the 88 pt gap and the 14 pt shorter navigation
        // bar. Set it from the pose's own height, as the real window has it.
        hc.traitOverrides.verticalSizeClass = pose.windowSize.height > 500 ? .regular : .compact
        hc.traitOverrides.preferredContentSizeCategory = type
        let window = UIWindow(windowScene: scene)
        // The window's own safe area comes from the sim screen it sits on and differs by sim pose (CI's Duo gave right 84, the
        // Mac's gave left 84), and a negative additionalSafeAreaInsets cannot cancel it. So every pose is hosted as a child
        // view of exactly the pose's size inside a small window in the middle of the screen: a window that touches no screen
        // edge has no safe area, the oversized child inherits none, and the pose's insets are exactly the ones added below.
        // Views outside a window's bounds are still laid out.
        let screen = scene.screen.bounds.size
        let hostShift = CGPoint.zero
        let shell = UIViewController()
        shell.view.clipsToBounds = false
        shell.addChild(hc)
        shell.view.addSubview(hc.view)
        hc.view.frame = CGRect(origin: .zero, size: pose.windowSize)
        hc.didMove(toParent: shell)
        let side = min(200, screen.width / 3, screen.height / 3)
        window.frame = CGRect(x: (screen.width - side) / 2, y: (screen.height - side) / 2, width: side, height: side)
        window.rootViewController = shell
        window.isHidden = false
        // The window inherits a safe area from the scene's real screen (the sim's own camera side), which would add to the
        // pose's. Lay out once with none added, read what was inherited, then add only the difference.
        window.layoutIfNeeded()
        hc.view.layoutIfNeeded()
        let inherited = hc.view.safeAreaInsets
        var t = pose.safeArea
        if pose.tabBarSuppliesTrailingInset { t.right = 0 }
        // `insetAdjust` is for width calibration only (HarnessWidthCalibrationTests); every asserting test passes none.
        hc.additionalSafeAreaInsets = UIEdgeInsets(top: t.top - inherited.top + insetAdjust.top, left: t.left - inherited.left + insetAdjust.left,
                                                   bottom: t.bottom - inherited.bottom + insetAdjust.bottom, right: t.right - inherited.right + insetAdjust.right)
        // Wait for the layout to settle, not for a fixed number of passes: at least `settle` (the splash, about 1.1 s), then until the
        // reported frames are identical for three passes in a row, up to 8 s. Whatever the app does after that is not "settled".
        let step = Duration.milliseconds(150)
        let start = ContinuousClock.now
        var passes = 0, same = 0
        var last: [CGRect] = [], lastNamed: [String: CGRect] = [:]
        while true {
            window.layoutIfNeeded()
            try? await Task.sleep(for: step)
            passes += 1
            same = (box.frames == last && box.named == lastNamed) ? same + 1 : 0
            last = box.frames; lastNamed = box.named
            let elapsed = ContinuousClock.now - start
            if elapsed >= settle && same >= 3 { break }
            if elapsed >= .seconds(8) { break }
        }
        let origin = CGPoint(x: hostShift.x + pose.safeArea.left, y: hostShift.y + pose.safeArea.top)
        func rel(_ r: CGRect) -> CGRect { r.offsetBy(dx: -origin.x, dy: -origin.y) }
        var r = Rendered(pose: pose, livePose: model.livePose, frames: box.frames.map(rel),
                         named: box.named.mapValues(rel), window: window, controller: hc)
        r.settled = same >= 3
        r.passes = passes
        r.viewSize = hc.view.bounds.size
        r.appliedInsets = hc.view.safeAreaInsets
        r.inheritedInsets = inherited
        // Diagnostics for the next calibration: where the 84 pt leading offset on the Mac comes from.
        let all = box.frames.map { ("frame", $0) } + box.named.map { ($0.key, $0.value) }
        let leftmost = all.min { $0.1.minX < $1.1.minX }.map { "\($0.0) \($0.1)" } ?? "none"
        let sceneNote = screen.width > screen.height ? "landscape \(scene.interfaceOrientation.rawValue)" : "portrait \(scene.interfaceOrientation.rawValue)"
        let rawMinX = (box.frames + Array(box.named.values)).map(\.minX).min() ?? .nan
        print("harness error: [info, diag] \(pose.id) window \(window.frame) host in window \(hc.view.convert(CGPoint.zero, to: nil)) host in screen \(hc.view.convert(CGPoint.zero, to: window.screen.coordinateSpace)) margins \(hc.view.layoutMargins) safe \(hc.view.safeAreaInsets) additional \(hc.additionalSafeAreaInsets) origin \(origin) rawMinX \(rawMinX) leftmost \(leftmost) scene \(sceneNote) screen \(screen)")
        return r
    }

    /// The rendered pose as a PNG, at 1x, the size of the window the pose needs. Hosted offscreen, so the system's own navigation
    /// bar, Tabletop rail and hinge are not faithful (docs/fold-harness.md); this is for app-owned layout.
    static func png(_ r: Rendered) -> Data? {
        let size = r.pose.windowSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // The system's own bars float over the page offscreen, where the Duo draws them in its own place (docs/fold-harness.md), so
        // they are hidden for the still and put back after. What is left is the app's own layout.
        var hidden: [UIView] = []
        func hideChrome(_ v: UIView) {
            let name = String(describing: Swift.type(of: v))
            if !v.isHidden, ["TabBar", "NavigationBar", "FloatingBar", "PocketView", "Toolbar"].contains(where: name.contains) {
                v.isHidden = true; hidden.append(v); return
            }
            v.subviews.forEach(hideChrome)
        }
        hideChrome(r.controller.view)
        defer { hidden.forEach { $0.isHidden = false } }
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            r.controller.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        return image.pngData()
    }

    /// Tear down so the next pose starts clean.
    static func dispose(_ r: Rendered) {
        r.window.isHidden = true
        r.window.rootViewController = nil
    }
}
