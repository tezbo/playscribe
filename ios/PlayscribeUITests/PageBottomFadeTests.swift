import XCTest

/// R-7, the page's bottom edge (Quinn on #521 at 7cb8b33 and #526 at 722c752): the one-column page fades out over its last 24 pt,
/// and nothing of the list shows bright below that fade. The scroll view draws its rows on into the bottom safe area, under its own
/// frame, so the fade alone read inverted in Closed AX5 (a row dim at its top and bright at its bottom) and striped in Open
/// landscape (dim, bright, dim). Measured as pixel luminance, at rest and after a slow drag, in whatever pose the simulator is in.
/// Skips where the list is not the one-column page (Book and Tabletop list in the Contents).
@MainActor
final class PageBottomFadeTests: XCTestCase {
    func testNothingBrightBelowThePageFade() throws {
        let app = XCUIApplication()
        ReleaseRowTests.openBluePrince(app)
        let page = app.scrollViews["pageScroll"]
        XCTAssertTrue(page.waitForExistence(timeout: 10), "page shown [\(ReleaseRowTests.pose(app))]")
        guard page.isHittable else { throw XCTSkip("no one-column page [\(ReleaseRowTests.pose(app))]") }
        sleep(2)
        for step in ["rest", "dragged"] {
            if step == "dragged" {
                let from = page.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
                from.press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)),
                           withVelocity: .slow, thenHoldForDuration: 0.6)
                sleep(1)
            }
            let shot = app.screenshot()
            let window = app.windows.firstMatch.frame
            let f = page.frame
            var x0 = f.minX + 20, x1 = f.minX + 20 + min(160, f.width * 0.4)
            // Leave out anything drawn over the page's foot on purpose: tab bar items, the pill.
            for e in app.tabBars.buttons.allElementsBoundByIndex + app.buttons.matching(identifier: "pill").allElementsBoundByIndex
            where e.exists && e.frame.minY < window.maxY && e.frame.maxY > f.maxY - 4 {
                if e.frame.minX < x1 && e.frame.maxX > x0 { x1 = min(x1, e.frame.minX - 2) }
            }
            XCTAssertGreaterThan(x1 - x0, 20, "a clear column to measure at the page's foot [\(ReleaseRowTests.pose(app))]")
            // The last 4 pt of the fade, then up to 16 pt below the page's frame, to the screen edge.
            let fadeEnd = CGRect(x: x0, y: f.maxY - 4, width: x1 - x0, height: 4)
            let below = CGRect(x: x0, y: f.maxY + 1, width: x1 - x0, height: max(0, min(16, window.maxY - f.maxY - 1)))
            let a = SectionBarTests.maxLuminance(in: fadeEnd, of: shot.image)
            XCTAssertLessThan(a, 0.25, "the fade ends in page ink: max luminance \(a) in \(fadeEnd) (\(step)) [\(ReleaseRowTests.pose(app))]")
            if below.height > 0 {
                let b = SectionBarTests.maxLuminance(in: below, of: shot.image)
                XCTAssertLessThan(b, 0.25, "nothing bright below the fade: max luminance \(b) in \(below) (\(step)) [\(ReleaseRowTests.pose(app))]")
            }
            let att = XCTAttachment(screenshot: shot)
            att.name = "page-foot-\(step) [\(ReleaseRowTests.pose(app))]"; att.lifetime = .keepAlways; add(att)
        }
    }
}
