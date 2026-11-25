import XCTest

/// bug-psplus-card-missing-cover-empty-grid and r060-psplus-compact-ax3 (#646): the PS Plus card's titles are Buttons in Tabletop
/// (std and AX5) and in Open landscape at AX5. sim-use's swipes never reached the card there (runs 45546236061, 45550845539), so
/// XCUITest scrolls to it instead. plus-demo's lineup titles match nothing in the index, so both draw the no-art tile: the case
/// that used to be a bare label. In Tabletop every one sits below the fold (nothing tappable above it). Inner display only: CI
/// folds open with sim-use first (ios-ui.yml, inner step).
@MainActor
final class PlusCardPoseTests: XCTestCase {
    private static let titles = ["QA Game One", "QA Game Two"]

    /// `inner`: the Duo folded open (Tabletop, Open); otherwise the outer display, Closed, turned to landscape with the device.
    private func check(pose: String?, ax5: Bool, landscape: Bool, inner: Bool = true) {
        continueAfterFailure = true
        let app = XCUIApplication()
        var args = ["-qaRoute", "plus-demo"]
        if let pose { args += ["-qaPose", pose] }
        if ax5 { args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if !inner && landscape { args += ["-qaOrientation", "landscape"] }
        app.launchArguments = args
        app.launch()
        let tag = "\(pose ?? (inner ? "open" : "closed"))\(landscape ? " landscape" : "") \(ax5 ? "AX5" : "std")"
        if !inner && landscape {
            XCUIDevice.shared.orientation = .landscapeLeft
            let deadline = Date().addingTimeInterval(15)
            while app.windows.firstMatch.frame.width <= app.windows.firstMatch.frame.height && Date() < deadline { sleep(1) }
            sleep(2)
        }
        defer { if !inner && landscape { XCUIDevice.shared.orientation = .portrait } }
        let window = app.windows.firstMatch.frame
        print("plusWindow \(tag): \(window)")
        guard (min(window.width, window.height) >= 600) == inner, (window.width > window.height) == landscape else {
            XCTFail("\(tag): needs the \(inner ? "inner" : "outer") display in \(landscape ? "landscape" : "portrait"); the window is \(window), so this run measures nothing")
            app.terminate()
            return
        }
        let card = app.descendants(matching: .any)["plusCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 40), "\(tag): the PS Plus card is not in the Library")
        func button(_ t: String) -> XCUIElement { card.buttons[t] }
        // Whole, not just hittable: Open landscape AX5 stopped with the covers half under the window edge (ui run 45572488568).
        func reached() -> Bool {
            let w = app.windows.firstMatch.frame
            return Self.titles.allSatisfy { button($0).exists && button($0).isHittable && w.contains(button($0).frame) }
        }
        // Swipe the lowest scroll view (Tabletop's lower half; the one page elsewhere) until both titles are tappable.
        var swipes = 0
        while !reached() && swipes < 15 {
            let views = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            guard let page = views.max(by: { $0.frame.maxY < $1.frame.maxY }) else { break }
            page.swipeUp(velocity: .slow)
            swipes += 1
        }
        print("plusSwipes \(tag): \(swipes)")
        for t in Self.titles {
            let all = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", t)).allElementsBoundByIndex.filter { $0.frame.width > 0 }
            print("plusTitle \(tag): \(t) " + all.map { "\($0.elementType.rawValue) \($0.frame)" }.joined(separator: "; "))
            XCTAssertTrue(all.allSatisfy { $0.elementType == .button }, "\(tag): \(t) must be a Button, never a bare label")
            let b = button(t)
            XCTAssertTrue(b.exists, "\(tag): \(t) is not a Button in the card")
            XCTAssertTrue(b.isHittable, "\(tag): \(t) is not tappable")
            XCTAssertTrue(window.contains(b.frame), "\(tag): \(t) is cut by the window, \(b.frame)")
        }
        // Iris (#646): every cover, art or no-art tile, takes the same 3:4 frame, no wider than a Library tile (140 pt).
        let frames = Self.titles.map { button($0).frame }
        print("plusFrames \(tag): \(frames)")
        if let first = frames.first {
            for f in frames {
                XCTAssertEqual(f.width, first.width, accuracy: 1, "\(tag): covers differ in width, \(frames)")
                XCTAssertEqual(f.height, first.height, accuracy: 1, "\(tag): covers differ in height, \(frames)")
            }
            XCTAssertLessThanOrEqual(first.width, 141, "\(tag): wider than a Library tile")
            XCTAssertEqual(first.height / max(first.width, 1), 4.0 / 3.0, accuracy: 0.05, "\(tag): not 3:4, \(first)")
        }
        if pose == "tabletop" {
            let probe = app.descendants(matching: .any)["poseProbe"]
            print("plusPose \(tag): \(probe.exists ? probe.label : "no probe")")
            var foldBottom: CGFloat?
            if let data = probe.label.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = obj["division"] as? [Double], d.count == 4, d[2] > d[3] { foldBottom = CGFloat(d[1] + d[3]) }
            XCTAssertNotNil(foldBottom, "\(tag): no horizontal fold in the pose probe")
            if let foldBottom {
                for t in Self.titles {
                    XCTAssertGreaterThanOrEqual(button(t).frame.minY, foldBottom, "\(tag): \(t) is above the fold (rule: nothing tappable above it)")
                }
            }
        }
        // The still for the signers (Quinn, Iris): kept in the inner step's xcresult.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "plus-card \(tag)"
        shot.lifetime = .keepAlways
        add(shot)
        // A title opens its page (the bug: the no-art title could not be opened).
        if button(Self.titles[0]).isHittable {
            button(Self.titles[0]).tap()
            XCTAssertTrue(app.descendants(matching: .any)["gameBack"].waitForExistence(timeout: 10), "\(tag): the no-art title did not open its page")
        }
        app.terminate()
    }

    func testTabletopStd() { check(pose: "tabletop", ax5: false, landscape: false) }
    func testTabletopAX5() { check(pose: "tabletop", ax5: true, landscape: false) }
    /// The runner's Duo folded to 180 in landscape-left with no -qaPose: Open landscape.
    func testOpenLandscapeAX5() { check(pose: nil, ax5: true, landscape: true) }
    /// Closed (outer display), where sim-use's swipes stopped short of the card at AX5 (run 45557597743).
    func testClosedPortraitAX5() { check(pose: nil, ax5: true, landscape: false, inner: false) }
    func testClosedLandscapeAX5() { check(pose: nil, ax5: true, landscape: true, inner: false) }
}
