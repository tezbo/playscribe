import SwiftUI
import UIKit
@testable import Playscribe

/// Host one SwiftUI view (a sheet or panel's content, such as SettingsView) at a pose's size, Dynamic Type and optional extra
/// height, so a screen the app presents as a system sheet can be captured and checked headlessly. Advisory, like every harness
/// still: no system chrome, no real sheet, no hinge (docs/fold-harness.md).
extension FoldHost {
    /// `heightScale` > 1 hosts the view in a window taller than the pose, to see more of a scrolling screen (HARNESS_TALL).
    static func renderView<V: View>(_ content: V, pose: HarnessPose, type: UIContentSizeCategory = .large,
                                    model: AppModel = demoModel(), heightScale: CGFloat = 1,
                                    settle: Duration = .milliseconds(1500)) async -> Rendered? {
        guard let scene = hostScene() else { return nil }
        NSTimeZone.default = TimeZone(identifier: "Australia/Sydney") ?? .current
        var tall = pose
        if heightScale > 1 { tall.container.height *= heightScale }
        let root = content
            .environment(model)
            .environment(\.injectedRegions, tall.regions)
            .environment(\.railWidth, 0)
            .preferredColorScheme(.dark)
            .font(PlayscribeFont.body)
            .tint(PlayscribeColor.accent)
            .foregroundStyle(PlayscribeColor.textPrimary)
            .background(Color.ink0)
        let hc = UIHostingController(rootView: root)
        hc.traitOverrides.horizontalSizeClass = tall.compactWidth ? .compact : .regular
        hc.traitOverrides.verticalSizeClass = tall.windowSize.height > 500 ? .regular : .compact
        hc.traitOverrides.preferredContentSizeCategory = type
        let window = UIWindow(windowScene: scene)
        let screen = scene.screen.bounds.size
        let shell = UIViewController()
        shell.view.clipsToBounds = false
        shell.addChild(hc)
        shell.view.addSubview(hc.view)
        hc.view.frame = CGRect(origin: .zero, size: tall.windowSize)
        hc.didMove(toParent: shell)
        let side = min(200, screen.width / 3, screen.height / 3)
        window.frame = CGRect(x: (screen.width - side) / 2, y: (screen.height - side) / 2, width: side, height: side)
        window.rootViewController = shell
        window.isHidden = false
        window.layoutIfNeeded()
        hc.view.layoutIfNeeded()
        let inherited = hc.view.safeAreaInsets
        let t = tall.safeArea
        hc.additionalSafeAreaInsets = UIEdgeInsets(top: t.top - inherited.top, left: t.left - inherited.left,
                                                   bottom: t.bottom - inherited.bottom, right: t.right - inherited.right)
        let start = ContinuousClock.now
        while ContinuousClock.now - start < settle {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(150))
        }
        var r = Rendered(pose: tall, livePose: tall.expected, frames: [], named: [:], window: window, controller: hc)
        r.viewSize = hc.view.bounds.size
        r.appliedInsets = hc.view.safeAreaInsets
        r.inheritedInsets = inherited
        return r
    }
}
