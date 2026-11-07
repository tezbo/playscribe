import SwiftUI
import UIKit
@testable import Playscribe

/// One pose's container exactly as the app sees it: the size DuoReader's proxy reports, the safe area, the width size
/// class and the active fold, in the container's own coordinates (docs/fold-harness.md).
struct HarnessPose: Identifiable, CustomStringConvertible {
    enum Source: String {
        /// Read off the 0.5.0 Mac stills' debug overlay (size, fold). Safe area is assumed zero. Good enough to catch
        /// layout rules, not yet proven equal to the simulator.
        case provisional
        /// Captured by `PoseCaptureTests` in the Duo simulator and checked by `tools/qa/compare_harness.py`.
        case captured
    }

    var id: String
    var container: CGSize
    var safeArea = UIEdgeInsets.zero
    var compactWidth: Bool
    var division: CGRect?
    var occlusions: [CGRect] = []
    var expected: Pose
    var landscape: Bool { container.width > container.height }
    var source: Source = .provisional
    /// Insets inferred, not measured: layout rules are reported but not asserted until a sim run confirms them.
    var inferred = false
    var description: String { id }
    /// Poses with an 84 pt trailing safe area (Closed, Open, Book): on the Duo the system's vertical tab bar lives inside that region.
    /// Offscreen the tab view draws its own ~84 pt bar on top of an added 84 pt inset, so the harness counts it twice and every frame
    /// came out 84 pt narrow (calibration, #360: Closed deck 262 pt with the inset added, 346 pt without). FoldHost therefore leaves
    /// that trailing inset out and lets the tab bar supply it. Closed is verified; Open and Book are assumed the same, not yet read.
    var tabBarSuppliesTrailingInset: Bool { safeArea.right >= 80 }

    var regions: InjectedRegions { InjectedRegions(division: division, occlusions: occlusions) }
}

extension HarnessPose {
    /// The window the container lives in: container plus safe area.
    var windowSize: CGSize {
        CGSize(width: container.width + safeArea.left + safeArea.right, height: container.height + safeArea.top + safeArea.bottom)
    }

    /// The six poses the gate covers. Container sizes and folds are DuoReader's own numbers from the Mac stills (2a56de7).
    /// Safe areas, occlusions and the Book fold height come from the first sim calibration (227-calibration.txt, 744fe8f);
    /// the Closed landscape row from the second calibration (e0773f2: the camera side is leading, 84 pt). Safe-area order here
    /// is top, left, bottom, right; the probe prints top, leading, bottom, trailing.
    static let catalog: [HarnessPose] = [
        HarnessPose(id: "closed", container: CGSize(width: 382, height: 644), safeArea: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
                    compactWidth: true,
                    occlusions: [CGRect(x: 399.5, y: 29.5, width: 37, height: 37), CGRect(x: 382, y: 0, width: 84, height: 174)],
                    expected: .closed),
        HarnessPose(id: "closedLandscape", container: CGSize(width: 594, height: 432), safeArea: UIEdgeInsets(top: 0, left: 84, bottom: 34, right: 0),
                    compactWidth: true,
                    occlusions: [CGRect(x: -54.5, y: 29.5, width: 37, height: 37), CGRect(x: -84, y: 0, width: 84, height: 82)],
                    expected: .closed),
        HarnessPose(id: "open", container: CGSize(width: 867, height: 635), safeArea: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
                    compactWidth: false, occlusions: [CGRect(x: 867, y: 0, width: 84, height: 124)], expected: .flat),
        HarnessPose(id: "openPortrait", container: CGSize(width: 669, height: 835), safeArea: UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 0),
                    compactWidth: false, occlusions: [CGRect(x: 525, y: -82, width: 144, height: 82)], expected: .flat),
        HarnessPose(id: "book", container: CGSize(width: 867, height: 635), safeArea: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
                    compactWidth: false, division: CGRect(x: 455.5, y: 0, width: 40, height: 669),
                    occlusions: [CGRect(x: 867, y: 0, width: 84, height: 124)], expected: .book),
        HarnessPose(id: "tabletop", container: CGSize(width: 669, height: 835), safeArea: UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 0),
                    compactWidth: false, division: CGRect(x: 0, y: 373.5, width: 669, height: 40),
                    occlusions: [CGRect(x: 525, y: -82, width: 144, height: 82)], expected: .tabletop),
    ]

    static func named(_ id: String) -> HarnessPose { catalog.first { $0.id == id }! }
}
