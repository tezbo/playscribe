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

/// Quinn's condition on #379: show what the overlap rule sees on the game page, where Mac 48056df shows the Contents chip row on
/// the "All patch notes" link row in Open and Book. Reported, not asserted: it prints how many tappable frames the harness
/// captured and every crossing pair, so a blind spot is visible in the CI log instead of assumed.
@MainActor
@Suite(.serialized)
struct GamePageOverlapProbeTests {
    @Test(.timeLimit(.minutes(2)), arguments: ["closed", "open", "openPortrait", "book"], [0, 1])
    func gamePageOverlapProbe(_ id: String, _ sizeIndex: Int) async throws {
        let model = FoldHost.demoModel()
        model.handle(url: try #require(URL(string: "playscribe://game/kcd2")))
        let size: UIContentSizeCategory = sizeIndex == 0 ? .large : .accessibilityExtraExtraExtraLarge
        let r = try #require(await HarnessRules.timedRender(HarnessPose.named(id), type: size, model: model))
        defer { FoldHost.dispose(r) }
        let pairs = HarnessRules.overlappingPairs(r.frames)
        let label = sizeIndex == 0 ? "std" : "AX5"
        print("harness error: [info, probe] game page \(id) \(label): \(r.frames.count) tappable frames, \(pairs.count) crossing pair(s): \(pairs.prefix(6)); named: \(r.named.keys.sorted())")
    }
}

/// r054-probe-updates-tab: the Updates tab (`many-updates/updates`) in every pose, unasserted. Prints the tappable frames that cross each
/// other and the ones that enter a reserved occlusion (the Closed clock ring and badge/nav region where #382 found rows and tap
/// frames running under the rail). Read before and after #382 (319e85b) to see whether the harness can see that class of bug.
@MainActor
@Suite(.serialized)
struct UpdatesTabProbeTests {
    @Test(.timeLimit(.minutes(2)), arguments: ["closed", "open", "openPortrait", "book"], [0, 1])
    func updatesTabProbe(_ id: String, _ sizeIndex: Int) async throws {
        let model = FoldHost.demoModel()
        model.handle(url: try #require(URL(string: "playscribe://many-updates/updates")))
        let size: UIContentSizeCategory = sizeIndex == 0 ? .large : .accessibilityExtraExtraExtraLarge
        let r = try #require(await HarnessRules.timedRender(HarnessPose.named(id), type: size, model: model))
        defer { FoldHost.dispose(r) }
        let pairs = HarnessRules.overlappingPairs(r.frames)
        var entered: [String] = []
        for f in r.frames where f.width > 8 && f.height > 8 {
            for o in r.pose.occlusions {
                let x = f.intersection(o)
                if !x.isNull, x.width > 4, x.height > 4 { entered.append("\(HarnessRules.brief(f)) in \(HarnessRules.brief(o))") }
            }
        }
        let label = sizeIndex == 0 ? "std" : "AX5"
        print("harness error: [info, probe] updates tab \(id) \(label): tab \(model.nav.tab), \(r.frames.count) tappable frames, \(pairs.count) crossing pair(s): \(pairs.prefix(6)); \(entered.count) frame(s) inside an occlusion: \(entered.prefix(6))")
    }
}
