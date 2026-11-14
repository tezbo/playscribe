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

    /// R-7 (test-pinned-bar-luminance): nothing scrolls, sliced, in the gap between the scroll view's top edge and the pinned bar.
    /// The bug only shows where the scroll view has a top inset (Open landscape, Book; Mac at ad665e9: "Hotfix 1.0.3", "Patch 1.7"),
    /// so run it in those poses: in Closed the gap is empty either way. Rather than one strip after a fling to the end (green at
    /// 43a1d69, where the bug showed), it drags slowly, a row at a time, and at each stop measures the whole gap over the middle
    /// half of the bar's width (clear of the status bar's clock and icons). Skips in Tabletop, where the bar is outside the scroll.
    func testNothingShowsAboveThePinnedBar() throws {
        let app = XCUIApplication()
        ReleaseRowTests.openBluePrince(app)
        let pose = ReleaseRowTests.pose(app)
        guard !pose.contains("tabletop") else { throw XCTSkip("Tabletop pins the bar outside its scroll [\(pose)]") }
        let bar = app.descendants(matching: .any)["sectionBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "section bar shown [\(pose)]")
        let page = app.scrollViews["pageScroll"], contents = app.scrollViews["contentsScroll"]
        let list = contents.exists && contents.isHittable ? contents : page
        XCTAssertTrue(list.exists, "a scrolling list")

        var measured = 0, worst = 0.0, worstAt = CGRect.zero
        var lastBarY = CGFloat.nan
        for step in 0..<16 {
            // A slow drag of about one row, so a row stops part-way under the bar instead of flinging past it.
            let from = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            from.press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
            let f = bar.frame
            defer { lastBarY = f.minY }
            // Pinned once the bar stops moving while the list scrolls on.
            guard abs(f.minY - lastBarY) < 0.5 else { continue }
            let top = list.frame.minY, bottom = f.minY - 6   // 6 pt: Book's header padding is the bar's own ink
            guard bottom - top >= 4 else { continue }        // no gap above the bar in this pose
            let gap = CGRect(x: f.minX + f.width / 4, y: top, width: f.width / 2, height: bottom - top)
            let lum = Self.maxLuminance(in: gap, of: app.screenshot().image)
            measured += 1
            if lum > worst { worst = lum; worstAt = gap }
            if lum >= 0.25 {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "above-pinned-bar step \(step) [\(pose)]"; shot.lifetime = .keepAlways; add(shot)
            }
        }
        if measured == 0 { throw XCTSkip("no gap above the pinned bar in this pose [\(pose)]") }
        XCTAssertLessThan(worst, 0.25, "list text above the pinned bar: max luminance \(worst) in \(worstAt) over \(measured) stops [\(pose)]")
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
