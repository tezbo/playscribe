import XCTest

/// 0.5.6 hotfix, bug-055-rail-icons-shift (Terry, 14 Nov: the icons changed between poses, and in Tabletop they were half hidden
/// and scrolled). Iris's set, the same in every pose and at every text size: Back, Notifications, Status (absent for an untracked
/// game), More. More holds Check for updates, Links, Share, and Swap sides only while the pages are side by side.
/// Every button is whole and tappable without scrolling. In Tabletop every one sits below the fold and above the tab capsule.
/// Closed runs as-is; Book and Tabletop run on the synthetic fold (-qaPose). Open runs on the Mac.
@MainActor
final class RailSetTests: XCTestCase {
    private static let ax5 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    private func launch(pose: String?, ax5: Bool, route: String = "gamepage/dawnwalker") -> XCUIApplication {
        continueAfterFailure = true
        let app = XCUIApplication()
        var args = ["-qaRoute", route]
        if let pose { args += ["-qaPose", pose] }
        if ax5 { args += Self.ax5 }
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["foldAudit"].waitForExistence(timeout: 40), "the game page did not load")
        sleep(2)
        return app
    }

    /// The fold's lower edge from the pose probe, or nil when the pose has no horizontal fold.
    private func foldBottom(_ app: XCUIApplication) -> CGFloat? {
        let probe = app.descendants(matching: .any)["poseProbe"]
        guard probe.exists, let data = probe.label.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = obj["division"] as? [Double], d.count == 4, d[2] > d[3] else { return nil }
        return CGFloat(d[1] + d[3])
    }

    private func check(pose: String?, ax5: Bool, tracked: Bool = true) {
        // Untracked = not in the library, so no Status (Iris). The game page opens with Add to library (Quinn, #442).
        let route = tracked ? "gamepage/dawnwalker" : "gamepage/alan-wake-2"
        let app = launch(pose: pose, ax5: ax5, route: route)
        let tag = "\(pose ?? "closed") \(ax5 ? "AX5" : "std") \(tracked ? "tracked" : "untracked")"
        let window = app.windows.firstMatch.frame
        let ids = tracked ? ["gameBack", "rail.notify", "rail.status", "rail.more"] : ["gameBack", "rail.notify", "rail.more"]
        var frames: [CGRect] = []
        for id in ids {
            let all = app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex.filter { $0.frame.width > 0 }
            XCTAssertEqual(all.count, 1, "\(tag): \(id) should be on the rail exactly once, found \(all.count)")
            guard let e = all.first else { frames.append(.null); continue }
            XCTAssertTrue(e.isHittable, "\(tag): \(id) is not tappable without scrolling")
            XCTAssertTrue(window.contains(e.frame), "\(tag): \(id) is cut by the window edge, \(e.frame)")
            frames.append(e.frame)
        }
        // Labels, in Iris's words.
        XCTAssertEqual(app.descendants(matching: .any)["gameBack"].label, "Back to Library", tag)
        XCTAssertEqual(app.descendants(matching: .any)["rail.notify"].label, "Notifications", tag)
        if tracked { XCTAssertTrue(app.descendants(matching: .any)["rail.status"].label.hasPrefix("Status: "), tag) }
        else { XCTAssertFalse(app.descendants(matching: .any)["rail.status"].exists, "\(tag): an untracked game has no Status button") }
        XCTAssertEqual(app.descendants(matching: .any)["rail.more"].label, "More", tag)

        // None of these are rail buttons in any pose: they live behind More now.
        for gone in ["swapSides", "rail.refresh"] {
            XCTAssertFalse(app.descendants(matching: .any)[gone].exists, "\(tag): \(gone) is still a rail button")
        }

        let valid = frames.filter { !$0.isNull }
        guard valid.count == ids.count else { return }
        if let fold = foldBottom(app) {
            // Tabletop: one column, top to bottom, all below the fold and above the tab capsule.
            XCTAssertEqual(valid, valid.sorted { $0.minY < $1.minY }, "\(tag): the rail order changed")
            for (id, f) in zip(ids, valid) { XCTAssertGreaterThanOrEqual(f.minY, fold - 0.5, "\(tag): \(id) sits above the fold") }
            let tabs = app.buttons.matching(NSPredicate(format: "label == 'Library'")).allElementsBoundByIndex
                .filter { $0.frame.minX > window.width - 80 }
            if let capsule = tabs.first?.frame {
                XCTAssertLessThanOrEqual(valid.last!.maxY, capsule.minY, "\(tag): More runs into the tab capsule")
            } else {
                XCTFail("\(tag): no tab capsule on the rail")
            }
        } else {
            // A bar or a column (Closed's rail is a column): top to bottom, then leading to trailing on one line (Mac, 909fe8b:
            // Closed's column put Status at x 398.7 and Notifications at 399, so x alone misread the order).
            XCTAssertEqual(valid, valid.sorted { abs($0.minY - $1.minY) > 1 ? $0.minY < $1.minY : $0.minX < $1.minX },
                           "\(tag): the rail order changed")
        }
        app.terminate()
    }

    func testClosedStd() { check(pose: nil, ax5: false) }
    func testClosedAX5() { check(pose: nil, ax5: true) }
    func testBookStd() { check(pose: "book", ax5: false) }
    func testBookAX5() { check(pose: "book", ax5: true) }
    func testTabletopStd() { check(pose: "tabletop", ax5: false) }
    func testTabletopAX5() { check(pose: "tabletop", ax5: true) }
    func testTabletopUntrackedAX5() { check(pose: "tabletop", ax5: true, tracked: false) }
    func testClosedUntracked() { check(pose: nil, ax5: false, tracked: false) }

    /// D-10 survives behind More while the pages are side by side, and is listed nowhere else (Iris). One pose per test, so the
    /// Mac runs each in its matching simulator pose (-qaPose switches the app, not the simulator's fold: Mac, 729eaa5).
    private func moreLists(swapSides expected: Bool, pose: String?) {
        let app = launch(pose: pose, ax5: false)
        let more = app.descendants(matching: .any)["rail.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no More in \(pose ?? "closed")")
        more.tap()
        XCTAssertTrue(app.buttons["Check for updates"].waitForExistence(timeout: 5), "More did not open in \(pose ?? "closed")")
        XCTAssertEqual(app.buttons["Swap sides"].exists, expected, "Swap sides in \(pose ?? "closed")'s More")
        app.terminate()
    }

    func testMoreListsSwapSidesInBook() { moreLists(swapSides: true, pose: "book") }
    func testMoreHasNoSwapSidesInClosed() { moreLists(swapSides: false, pose: nil) }
    func testMoreHasNoSwapSidesInTabletop() { moreLists(swapSides: false, pose: "tabletop") }
}
