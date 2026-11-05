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
    var description: String { id }

    var regions: InjectedRegions { InjectedRegions(division: division, occlusions: occlusions) }
}

extension HarnessPose {
    /// The six poses the gate covers. Sizes are the points DuoReader reported in the 0.5.0 Mac stills (2a56de7);
    /// the folds are the 40 pt reserved band measured from the same stills (book 455 to 495 across, as the fold audit
    /// printed; tabletop 374 to 414 down).
    static let catalog: [HarnessPose] = [
        HarnessPose(id: "closed", container: CGSize(width: 382, height: 644), compactWidth: true, expected: .closed),
        HarnessPose(id: "closedLandscape", container: CGSize(width: 594, height: 432), compactWidth: true, expected: .closed),
        HarnessPose(id: "open", container: CGSize(width: 867, height: 635), compactWidth: false, expected: .flat),
        HarnessPose(id: "openPortrait", container: CGSize(width: 669, height: 835), compactWidth: false, expected: .flat),
        HarnessPose(id: "book", container: CGSize(width: 867, height: 635), compactWidth: false,
                    division: CGRect(x: 455, y: 0, width: 40, height: 635), expected: .book),
        HarnessPose(id: "tabletop", container: CGSize(width: 669, height: 835), compactWidth: false,
                    division: CGRect(x: 0, y: 374, width: 669, height: 40), expected: .tabletop),
    ]

    static func named(_ id: String) -> HarnessPose { catalog.first { $0.id == id }! }
}
