import XCTest

/// PP-1 (pose parity, 0.5.5): the game page offers the same content in every pose (Terry, 13 Nov: Tabletop had no genres, About,
/// trailer rows or links in its lower half, and nothing in the matrix could say so). Layout may differ by pose; whether an item
/// exists and can be reached may not. In Tabletop only the lower half counts: the upper stage is view-only and never scrolls.
///
/// This test writes one dump per run (an attachment and a print), one line per item:
///   ITEM <name> present=<bool> reachable=<bool> half=<upper|lower|n/a> pose=<pose>
/// `tools/qa/pose_parity.py` compares the dumps of one game across poses and fails when a pose lacks an item another pose has.
/// Run it once per pose (Closed, Open portrait, Open landscape, Book via -qaPose book, Tabletop via -qaPose tabletop) and per
/// game: A tracked with notes (`gamepage/dawnwalker`), B tracked with no notes (`no-notes-page/<game>`), C untracked
/// (`no-notes-page/<game>/untracked`; the plain `no-notes` routes stay on the Library and never reach the page). Set PARITY_ROUTE and PARITY_POSE in the scheme's environment (or pass -qaRoute as usual).
@MainActor
final class PoseParityTests: XCTestCase {
    /// The items of docs/ux-acceptance.md PP-1 and how each is found. Labels are what VoiceOver reads.
    private struct Item { let name: String; let query: (XCUIApplication) -> XCUIElementQuery; let predicate: NSPredicate }

    private let items: [Item] = [
        Item(name: "about", query: { $0.staticTexts }, predicate: NSPredicate(format: "label == 'About'")),
        Item(name: "genres", query: { $0.staticTexts }, predicate: NSPredicate(
            format: "label MATCHES '.*(RPG|Role-playing|Action|Adventure|Shooter|Strategy|Simulator|Puzzle|Platform|Indie|Fighting|Racing|Sport).*' AND label CONTAINS[c] ', '")),
        // One item: Tabletop's "Play trailer" row stands for the trailer rows (Iris spec); other poses list each trailer.
        Item(name: "trailers", query: { $0.buttons }, predicate: NSPredicate(format: "label BEGINSWITH 'Play '")),
        // Link rows read "<title>, opens in browser" in the sheet and "Official website" inline, as buttons or links: any element.
        Item(name: "officialLink", query: { $0.descendants(matching: .any) }, predicate: NSPredicate(format: "label BEGINSWITH 'Official website'")),
        Item(name: "patchNotesLink", query: { $0.descendants(matching: .any) }, predicate: NSPredicate(format: "label BEGINSWITH 'All patch notes'")),
        Item(name: "youMightAlsoLike", query: { $0.staticTexts }, predicate: NSPredicate(format: "label == 'You might also like'")),
        // Drawn only while the game is not in the library; by identifier, as Closed's PageView header and the Contents both set it.
        Item(name: "addToLibrary", query: { $0.descendants(matching: .any) }, predicate: NSPredicate(format: "identifier == 'addToLibrary' OR label == 'Add to library'")),
    ]

    /// The fold's lower edge in the app's coordinates, from the probe JSON (`division`), or 0 when the pose has no horizontal fold.
    private func tabletopFoldBottom(_ app: XCUIApplication) -> CGFloat {
        let probe = app.descendants(matching: .any)["poseProbe"]
        guard probe.exists, let data = probe.label.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = obj["division"] as? [Double], d.count == 4 else { return 0 }
        // box = [x, y, w, h]
        return CGFloat(d[1] + d[3])
    }

    private func dump(route: String, pose: String?) throws {
        let app = XCUIApplication()
        var args = ["-qaRoute", route]
        if let pose { args += ["-qaPose", pose] }
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["foldAudit"].waitForExistence(timeout: 40), "the game page did not load")
        let poseLabel = ReleaseRowTests.pose(app)
        let base = poseLabel.components(separatedBy: "pose: ").last?.components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespaces) ?? "unknown"
        let tabletop = base == "tabletop"
        // Both Open orientations report pose=flat; the window's shape tells them apart so the dumps do not merge.
        let win = app.windows.firstMatch.frame
        let poseName = base == "flat" ? (win.width > win.height ? "openLandscape" : "openPortrait") : base
        let foldBottom = tabletop ? tabletopFoldBottom(app) : 0
        sleep(3) // the page's details load asynchronously (GameInfoStore)
        // A guard that never reached the game page would pass vacuously: fail instead.
        XCTAssertTrue(app.descendants(matching: .any)["statusGlyph"].exists
                      || app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Add to library' OR label == 'Check for updates' OR label BEGINSWITH 'Official website'")).count > 0
                      || app.staticTexts.matching(NSPredicate(format: "label == 'ALL UPDATES' OR label == 'All updates'")).count > 0,
                      "the route never opened the game page [\(route)]")

        var lines: [String] = []
        for item in items {
            let found = item.query(app).matching(item.predicate)
            // Reachable: Tabletop counts only what is in the lower half; every other pose counts anything on the page. An item far
            // down a scroll view still exists in the tree, so "present" is the tree; "reachable" adds the half rule.
            let present = found.count > 0
            var reachable = present
            var half = "n/a"
            if tabletop, present {
                let el = found.firstMatch
                let lower = el.frame.minY >= foldBottom - 0.5
                half = lower ? "lower" : "upper"
                reachable = lower
            }
            lines.append("ITEM \(item.name) present=\(present) reachable=\(reachable) half=\(half) pose=\(poseName)")
        }
        let text = lines.joined(separator: "\n")
        print("POSEPARITY route=\(route)\n\(text)")
        let a = XCTAttachment(string: text)
        a.name = "parity-\(route.replacingOccurrences(of: "/", with: "_"))-\(poseName).txt"
        a.lifetime = .keepAlways
        add(a)
        app.terminate()
    }

    func testDump() throws {
        let env = ProcessInfo.processInfo.environment
        let route = env["PARITY_ROUTE"] ?? "gamepage/dawnwalker"
        try dump(route: route, pose: env["PARITY_POSE"])
    }
}
