import XCTest

/// R-7 (0.5.6, Card C), spec acceptance 4: the section bar (the picker at accessibility sizes, the table of contents in Book) stays
/// on screen at every scroll position, in whatever pose the simulator is in. Blue Prince has the longest update list in the
/// fixtures, so the end of its What's new is far below the bar.
@MainActor
final class SectionBarTests: XCTestCase {
    func testBarStaysVisibleAtTheEndOfALongList() throws {
        let app = XCUIApplication()
        ReleaseRowTests.openBluePrince(app)
        let bar = app.descendants(matching: .any)["sectionBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "section bar shown [\(ReleaseRowTests.pose(app))]")

        // Scroll the list itself to its end: the one-column page, or the Contents in Book and Tabletop.
        let page = app.scrollViews["pageScroll"], contents = app.scrollViews["contentsScroll"]
        let list = contents.exists && contents.isHittable ? contents : page
        XCTAssertTrue(list.exists, "a scrolling list")
        for _ in 0..<14 { list.swipeUp(velocity: .fast) }
        sleep(1)

        let window = app.windows.firstMatch.frame
        XCTAssertTrue(bar.exists, "bar still in the tree at the end of the list")
        XCTAssertTrue(window.contains(bar.frame), "bar on screen at the end: \(bar.frame) in \(window)")
        XCTAssertTrue(bar.buttons.firstMatch.isHittable, "a section is tappable at the end of the list [\(ReleaseRowTests.pose(app))]")
        // Nothing scrolls, sliced, above the pinned bar (Mac at ad665e9: "Hotfix 1.0.3" above the bar in Open landscape, "Patch 1.7"
        // in Book). The 4 pt strip just above the bar is page ink: no text there. Tabletop pins the bar outside its scroll, under the
        // stage, so the strip above it is the fold, not the list. The strip starts 6 pt up, past Book's header padding.
        if !ReleaseRowTests.pose(app).contains("tabletop") {
            let strip = CGRect(x: bar.frame.minX, y: bar.frame.minY - 10, width: bar.frame.width, height: 4)
            let lum = Self.maxLuminance(in: strip, of: app.screenshot().image)
            XCTAssertLessThan(lum, 0.25, "no list text in the 4 pt strip just above the pinned bar: max luminance \(lum) in \(strip) [\(ReleaseRowTests.pose(app))]")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "section-bar-end [\(ReleaseRowTests.pose(app))]"; shot.lifetime = .keepAlways; add(shot)

        // Switching a section keeps the bar on screen and adds nothing to Back (Card D).
        let back = app.buttons["gameBack"]
        let backLabel = back.exists ? back.label : nil
        let news = bar.buttons["News"]
        if news.exists && news.isHittable {
            news.tap()
            sleep(1)
            XCTAssertTrue(bar.buttons.firstMatch.isHittable, "bar on screen after switching to News")
            if let backLabel { XCTAssertEqual(back.label, backLabel, "switching a section leaves Back as it was") }
        }
    }

    /// The brightest pixel (relative luminance, 0 to 1) in `rect`, given in points, of a screenshot.
    static func maxLuminance(in rect: CGRect, of image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 1 }
        let scale = CGFloat(cg.width) / image.size.width
        let px = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard px.width > 0, px.height > 0, let crop = cg.cropping(to: px) else { return 1 }
        let w = crop.width, h = crop.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        var top = 0.0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let l = (0.2126 * Double(bytes[i]) + 0.7152 * Double(bytes[i + 1]) + 0.0722 * Double(bytes[i + 2])) / 255
            top = max(top, l)
        }
        return top
    }
}
