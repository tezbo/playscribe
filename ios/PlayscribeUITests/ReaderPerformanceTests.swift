import XCTest

/// J-2d Scroll performance: scrolling the Dawnwalker Update 1.1 page (about 360 note items) must not
/// hitch. Run on a device or the Mac gate; record a baseline in Xcode's Report navigator (Set
/// Baseline) so later runs fail on regressions. Hitch metrics only mean something on real hardware.
@MainActor
final class ReaderPerformanceTests: XCTestCase {
    func testScrollingUpdate11() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "release/dawnwalker/dawnwalker@1.1"]
        app.launch()
        let page = app.scrollViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 15))
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric,
                          XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            page.swipeUp(velocity: .fast)
            page.swipeUp(velocity: .fast)
            page.swipeDown(velocity: .fast)
            page.swipeDown(velocity: .fast)
            stopMeasuring()
        }
    }

    /// Opening a section and showing all its lines stays quick.
    func testExpandingASectionIsQuick() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "release/dawnwalker/dawnwalker@1.1"]
        app.launch()
        let header = app.buttons.matching(NSPredicate(format: "label CONTAINS ','")).element(boundBy: 0)
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        measure(metrics: [XCTClockMetric()]) {
            header.tap()
            header.tap()
        }
    }
}
