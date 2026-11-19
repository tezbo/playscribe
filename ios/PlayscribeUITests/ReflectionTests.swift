import XCTest
import UIKit

/// R-11, Reflection mode (Terry's Duo test, 14 Nov, 0.5.5): the mirror is the live video itself, in Tabletop only. Outside Tabletop
/// there is none; in Tabletop there is none until the video plays, then there is one. Read from the player's `mirrorAudit`
/// accessibility label (INTERNAL builds), not from pixels: a screenshot shows only one display, and walking the YouTube web view's
/// texts timed out (Mac at fd95a88). Autoplay is off by default, so the video has not started when the test first looks.
@MainActor
final class ReflectionTests: XCTestCase {
    func testMirrorOnlyInTabletopAndOnlyWhilePlaying() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "video/dawnwalker/dawnwalker@1.1"]
        app.launch()
        let audit = app.descendants(matching: .any)["mirrorAudit"]
        XCTAssertTrue(audit.waitForExistence(timeout: 10), "mirror audit present")
        let pose = ReleaseRowTests.pose(app)
        // The pose in the run's output, so one log shows every pose the test covered (Quinn on #533).
        print("ReflectionTests pose: \(pose)")
        sleep(2)
        XCTAssertEqual(audit.label, "mirror: off", "no mirror before the video plays [\(pose)]")
        guard pose.contains("tabletop") else {
            // Outside Tabletop nothing turns it on: the player's own controls play the video, and the mirror stays off.
            sleep(3)
            XCTAssertEqual(audit.label, "mirror: off", "no mirror outside Tabletop [\(pose)]")
            print("ReflectionTests pose: \(pose) after waiting: \(audit.label)")
            return
        }
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10) && play.isHittable, "Play on the transport")
        play.tap()
        let on = expectation(for: NSPredicate(format: "label == %@", "mirror: on"), evaluatedWith: audit)
        wait(for: [on], timeout: 30)
        print("ReflectionTests pose: \(pose) mirror after Play: \(audit.label)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "reflection-playing [\(pose)]"; shot.lifetime = .keepAlways; add(shot)
        measureMirror(audit, pose: pose)
    }

    /// The pixels (19 Nov, Terry: "it's missing entirely" on his Duo while the label said on). Compares the brightest pixels of the
    /// mirror band with the brightest of the video over the same columns, on frames bright enough to tell. Columns 60 to 90% of the
    /// video's width: clear of the caption and its plate on the left and the rail on the right. The mirror must reach 40% of the
    /// video's brightness on at least one bright frame, or a person cannot see it.
    private func measureMirror(_ audit: XCUIElement, pose: String) {
        let g = (audit.value as? String ?? "").split(separator: " ").compactMap { Double($0) }
        guard g.count == 6, g[2] > 0, g[3] > 0, g[5] > 0 else { return XCTFail("mirror geometry missing: \(audit.value ?? "nil") [\(pose)]") }
        let video = CGRect(x: g[0], y: g[1], width: g[2], height: g[3])
        let band = CGRect(x: g[0], y: g[4], width: g[2], height: min(g[5], g[3] * 0.25))
        var best = 0.0
        for i in 0..<8 {
            let shot = XCUIApplication().screenshot()
            guard let src = MirrorPixels.peak(shot.image, video, columns: 0.6...0.9),
                  let mir = MirrorPixels.peak(shot.image, band, columns: 0.6...0.9) else { return XCTFail("screenshot unreadable [\(pose)]") }
            print("ReflectionTests pixels [\(pose)] frame \(i): video peak \(src), mirror peak \(mir)")
            if src >= 80 { best = max(best, Double(mir) / Double(src)) }
            if i == 0 || best < 0.4 {
                let a = XCTAttachment(screenshot: shot); a.name = "reflection-pixels-\(i) [\(pose)]"; a.lifetime = .keepAlways; add(a)
            }
            sleep(1)
        }
        print("ReflectionTests pixels [\(pose)] best mirror/video \(String(format: "%.2f", best))")
        XCTAssertGreaterThanOrEqual(best, 0.4, "the mirror is too faint to see, or not drawn: best \(best) of the video's peak [\(pose)]")
    }
}

/// Luminance from a screenshot, in the screenshot's own points.
enum MirrorPixels {
    /// The 99th-percentile luma (0 to 255) of `rect`, over the given share of its width.
    static func peak(_ image: UIImage, _ rect: CGRect, columns: ClosedRange<Double>) -> Int? {
        guard let cg = image.cgImage else { return nil }
        let s = image.scale
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let x0 = Int((rect.minX + rect.width * columns.lowerBound) * s), x1 = Int((rect.minX + rect.width * columns.upperBound) * s)
        let y0 = Int(rect.minY * s), y1 = Int(rect.maxY * s)
        var values: [Int] = []
        for y in stride(from: max(0, y0), to: min(h, y1), by: 2) {
            for x in stride(from: max(0, x0), to: min(w, x1), by: 2) {
                let i = (y * w + x) * 4
                values.append((299 * Int(px[i]) + 587 * Int(px[i + 1]) + 114 * Int(px[i + 2])) / 1000)
            }
        }
        guard !values.isEmpty else { return nil }
        values.sort()
        return values[min(values.count - 1, values.count * 99 / 100)]
    }
}
