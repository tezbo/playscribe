import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// r052-harness-ax-gaps: a screen taller than the panel must scroll at AX5 (the Add sheet could not, #292 follow-up).
/// Settings is hosted directly by `FoldHost.renderView` (a system sheet is not in the capture). Evidence only; the Mac is the sign-off.
@MainActor
@Suite(.serialized)
struct SheetScrollTests {
    /// The tallest scroll view under `view`: its viewport height, content height and whether it scrolls.
    static func scrollInfo(in view: UIView) -> (viewport: CGFloat, content: CGFloat, enabled: Bool)? {
        var best: UIScrollView?
        func walk(_ v: UIView) {
            if let s = v as? UIScrollView, s.bounds.height > 100, s.contentSize.height >= (best?.contentSize.height ?? 0) { best = s }
            v.subviews.forEach(walk)
        }
        walk(view)
        guard let s = best else { return nil }
        return (s.bounds.height, s.contentSize.height, s.isScrollEnabled)
    }

    @Test(.timeLimit(.minutes(2)), arguments: ["closed", "open", "openPortrait"])
    func settingsScrollsWhenTallerThanThePanelAtAX5(_ id: String) async throws {
        let pose = HarnessPose.named(id)
        let r = try #require(await FoldHost.renderView(SettingsView(), pose: pose, type: .accessibilityExtraExtraExtraLarge),
                             "\(id): a window scene to host in")
        defer { FoldHost.dispose(r) }
        guard let info = Self.scrollInfo(in: r.controller.view) else {
            HarnessRules.fail("\(id) AX5 G-8: Settings has no scroll view, so content past the panel is unreachable")
            return
        }
        print("harness error: [info, calib] \(id) AX5 Settings scroll: viewport \(Int(info.viewport)) content \(Int(info.content)) enabled \(info.enabled)")
        HarnessRules.require(info.enabled, "\(id) AX5 G-8: Settings scroll view is not scrollable")
        HarnessRules.require(info.content > info.viewport, "\(id) AX5 G-8: Settings at AX5 fits its \(Int(info.viewport)) pt viewport (\(Int(info.content)) pt), so the AX5 size is not being applied")
    }
}
