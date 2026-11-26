import XCTest

/// bug-landscape-rail-back-empty (R-6 rail set, the same in every pose). The game page opens on the outer display and the Duo is
/// then unfolded to landscape: after #619 the bar rebuilt itself on the inner display with an empty Back disc and no gameBack in
/// the tree (Duo poses run 45489150050), although a launch on an already-open Duo kept it (RailSetTests passed). So this test
/// launches Closed and waits for the unfold; CI's inner-display step folds the simulator with sim-use once the app is running
/// (.github/workflows/ios-ui.yml). On a Mac, unfold by hand within 180 s. Fails, never skips, when no unfold happens.
final class UnfoldBackTests: XCTestCase {
    private func backSurvivesUnfold(_ tag: String) {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "gamepage/dawnwalker"]
        app.launch()
        let back = app.descendants(matching: .any)["gameBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 40), "\(tag): no Back on the outer display before the unfold")
        let start = app.windows.firstMatch.frame
        guard min(start.width, start.height) < 600 else {
            XCTFail("\(tag): launched on the inner display (\(start)), so this run cannot see the unfold")
            app.terminate()
            return
        }
        let deadline = Date().addingTimeInterval(180)
        func inner() -> Bool { let w = app.windows.firstMatch.frame; return min(w.width, w.height) >= 600 && w.width > w.height }
        while !inner() && Date() < deadline { sleep(1) }
        let w = app.windows.firstMatch.frame
        print("unfoldWindow \(tag): \(start) -> \(w)")
        guard inner() else {
            XCTFail("\(tag): the Duo was not unfolded to landscape within 180 s (window \(w)); this run measures nothing")
            app.terminate()
            return
        }
        sleep(4) // the bar settles into the trailing rail
        let all = app.descendants(matching: .any).matching(identifier: "gameBack").allElementsBoundByIndex.filter { $0.frame.width > 0 }
        XCTAssertEqual(all.count, 1, "\(tag): Back should be on the rail exactly once after the unfold, found \(all.count)")
        if let e = all.first {
            XCTAssertEqual(e.label, "Back to Library", tag)
            XCTAssertTrue(e.isHittable, "\(tag): Back is not tappable")
            XCTAssertTrue(w.contains(e.frame), "\(tag): Back \(e.frame) is outside the window \(w)")
        }
        app.terminate()
    }

    /// CI unfolds to a 110 degree hinge: Book, a real division.
    func testBackSurvivesUnfoldToBook() { backSurvivesUnfold("unfold to Book") }
    /// CI unfolds flat (180 degrees): Open landscape.
    func testBackSurvivesUnfoldToOpenLandscape() { backSurvivesUnfold("unfold to Open landscape") }
}
