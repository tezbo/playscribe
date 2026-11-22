import XCTest

/// bug-library-redraw-on-feed-refresh: a feed refresh landing mid-scroll must not redraw the whole Library. Quinn at #513 04e6e6c,
/// Tabletop, 12 games, 20 fast swipes: the shelf body ran 33 times, about 24 of them from the refresh (AppModel.data and
/// feedStatus). Target: 8 or fewer in 20 swipes with refreshes landing throughout, in Closed and Tabletop.
/// `-qaFeedPulse 1` runs a refresh every second through the real apply path, with no network; the shelf's body count is read from
/// a hidden QA marker that is never observed, so reading it costs no run.
final class LibraryFeedRedrawTests: XCTestCase {
    static let limit = 8

    @MainActor func testFeedRefreshMidScrollRedrawsTheLibraryAtMostEightTimes() throws {
        let runs = try bodyRuns(during: 20, pulse: true)
        XCTAssertLessThanOrEqual(runs, Self.limit, "LibraryShelf body ran \(runs) times in 20 swipes with a feed refresh every second")
    }

    /// The same swipes with no refresh: separates scrolling's own runs from the feed's, for the Mac log.
    @MainActor func testScrollingAloneRedrawsTheLibraryAtMostEightTimes() throws {
        let runs = try bodyRuns(during: 20, pulse: false)
        XCTAssertLessThanOrEqual(runs, Self.limit, "LibraryShelf body ran \(runs) times in 20 swipes with no refresh")
    }

    @MainActor
    private func bodyRuns(during swipes: Int, pulse: Bool) throws -> Int {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "fill-library/12"] + (pulse ? ["-qaFeedPulse", "1"] : [])
        app.launch()
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 15), "the library shows tiles")
        let marker = app.staticTexts["qaLibraryBody"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "the QA body count marker is present")
        sleep(2)   // launch settles, and with the pulse on, a refresh or two have landed before counting starts
        let before = try count(marker)
        let page = app.scrollViews.firstMatch
        for i in 0..<swipes {
            if i < swipes / 2 { page.swipeUp(velocity: .fast) } else { page.swipeDown(velocity: .fast) }
        }
        sleep(1)
        let after = try count(marker)
        let pose = ReleaseRowTests.pose(app)
        let note = "\(pose); pulse \(pulse ? "on" : "off"); body runs \(after - before) (\(before) to \(after))"
        print("LibraryFeedRedraw: \(note)")
        XCTContext.runActivity(named: note) { _ in }
        return after - before
    }

    private func count(_ marker: XCUIElement) throws -> Int {
        let label = marker.label
        return try XCTUnwrap(Int(label.replacingOccurrences(of: "qa-library-body: ", with: "")), "marker label: \(label)")
    }
}
