import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// Closed landscape stills from the fold harness (docs/fold-harness.md), because the hosted runner cannot rotate the Duo's
/// outer panel (XCUIDevice orientation leaves 466x678). These are HARNESS output: frames are 84-88 pt off the real Duo, so
/// they are not a Closed landscape sign-off; that stays with the Mac gate. Writes PNGs only when HARNESS_SHOT_DIR is set
/// (ios-ui.yml), so the normal unit run is untouched.
@MainActor
struct HarnessLandscapeShotTests {
    @Test(arguments: [("", UIContentSizeCategory.large), ("-ax5", UIContentSizeCategory.accessibilityExtraExtraExtraLarge)])
    func libraryClosedLandscape(_ suffix: String, _ type: UIContentSizeCategory) async throws {
        guard let dir = ProcessInfo.processInfo.environment["HARNESS_SHOT_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let p = HarnessPose.named("closedLandscape")
        let r = try #require(await FoldHost.render(p, type: type), "a window scene to host in")
        defer { FoldHost.dispose(r) }
        let view = r.controller.view!
        let size = view.bounds.size
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 2
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            if !view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) {
                view.layer.render(in: ctx.cgContext)
            }
        }
        let png = try #require(img.pngData(), "png")
        try png.write(to: URL(fileURLWithPath: "\(dir)/harness-closed-land-library\(suffix).png"))
        #expect(size.width > size.height, "landscape")
    }
}
