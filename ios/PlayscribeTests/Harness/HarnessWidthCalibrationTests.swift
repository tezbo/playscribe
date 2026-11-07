import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// Calibration, not rules (docs/fold-harness.md, "frames 84-88 pt narrow"). Hypothesis: the harness adds the pose's 84 pt
/// trailing safe area AND the offscreen tab view draws its own ~88 pt vertical tab bar, where on the Duo the tab bar lives
/// inside that 84 pt region. Each variant renders Closed and prints the widest tappable frame, the deck width and what UIKit
/// reports for the tab bar, so one CI run says which adjustment makes the widths match the Duo (about 350 pt for the Closed
/// segmented control: 16 pt to 366 pt on the Mac stills). Prints only; asserts nothing.
@MainActor
struct HarnessWidthCalibrationTests {
    @Test(.timeLimit(.minutes(2)), arguments: [
        ("baseline", UIEdgeInsets.zero),
        ("trailing-84", UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -84)),
        ("trailing-88", UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -88)),
    ])
    func closedWidthVariants(_ name: String, _ adjust: UIEdgeInsets) async throws {
        let p = HarnessPose.named("closed")
        let r = try #require(await FoldHost.render(p, insetAdjust: adjust))
        defer { FoldHost.dispose(r) }
        let widest = r.frames.map(\.width).max() ?? 0
        let maxX = r.frames.map(\.maxX).max() ?? 0
        let deck = r.named["latestDeck"].map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "none"
        var bars: [String] = []
        func walk(_ v: UIView, _ depth: Int) {
            guard depth < 40 else { return }
            let n = String(describing: Swift.type(of: v))
            if n.contains("TabBar") || n.contains("VerticalBar") || n.contains("Pocket") {
                let f = v.convert(v.bounds, to: r.window)
                bars.append("\(n) \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))")
            }
            for s in v.subviews { walk(s, depth + 1) }
        }
        walk(r.window, 0)
        print("harness error: [info, calib] closed \(name): widest tappable \(Int(widest)) pt, rightmost edge \(Int(maxX)) (container \(Int(p.container.width))), deck \(deck), safe \(r.appliedInsets), bars \(bars.prefix(6))")
    }
}
