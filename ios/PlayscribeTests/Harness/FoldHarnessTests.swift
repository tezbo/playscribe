import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// The fold harness (docs/fold-harness.md): the real RootView laid out at each pose's exact container, fold and size
/// class in an offscreen UIKit window, with the layout rules asserted on the frames. No Device Hub, no pose driver.
///
/// Rules cited: G-4 (nothing tappable above the Tabletop fold), TT-0 (nothing crosses the fold), TB-1 (the Library
/// toolbar always shows Settings and Add), J-5 (the hero deck is bounded; e869273 had 835 x 727 pt).
@MainActor
struct FoldHarnessTests {
    // MARK: Pose derivation (pure)

    @Test(arguments: ["closed", "closedLandscape", "open", "openPortrait", "book", "tabletop"])
    func catalogPoseMatchesWhatDuoReaderDerives(_ id: String) {
        let p = HarnessPose.named(id)
        let ctx = DuoReader<EmptyView>.context(size: p.container, compact: p.compactWidth,
                                               division: p.division, occlusions: p.occlusions)
        #expect(ctx.pose == p.expected, "\(p.id)")
        if let fold = p.division {
            #expect(CGRect(origin: .zero, size: p.windowSize).contains(fold), "\(p.id): the fold lies inside the window (it runs under the bottom inset in the sim)")
        }
    }

    // MARK: Toolbar slots (TB-1)

    /// 551d8ce: Add and Settings shared one trailing group and the system dropped one in every pose but Tabletop. An
    /// offscreen window cannot show that, so assert the cause: every Library toolbar item has a slot of its own.
    @Test func libraryToolbarItemsEachHaveTheirOwnSlot() {
        let slots = [LibraryToolbar.settings, LibraryToolbar.add, LibraryToolbar.viewMenu]
        #expect(Set(slots).count == slots.count, "TB-1: two Library toolbar items share a slot: \(slots)")
        #expect(LibraryToolbar.settings == .leading, "TB-1: Settings leads, so it is never collapsed with Add")
    }

    // MARK: Layout rules at the default text size

    @Test(arguments: ["closed", "closedLandscape", "open", "openPortrait", "book", "tabletop"])
    func libraryRulesHold(_ id: String) async throws {
        let p = HarnessPose.named(id)
        let r = try #require(await FoldHost.render(p), "\(p.id): a window scene to host in")
        defer { FoldHost.dispose(r) }
        // `TEST_RUNNER_HARNESS_DUMP_DIR=/tmp/h xcodebuild test …` leaves <pose>.json for compare_harness.py.
        if let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? r.probeJSON.write(toFile: "\(dir)/\(p.id).json", atomically: true, encoding: .utf8)
        }
        HarnessRules.require(r.geometryProblem == nil, "\(p.id): the harness did not reproduce the pose geometry: \(r.geometryProblem ?? "")")
        HarnessRules.require(r.livePose == p.expected, "\(p.id): the injected fold gave pose \(r.livePose), expected \(p.expected)")
        // TT-0 is reported, not asserted, where the system lays pages out (ArrangementView splits at the window's real
        // reserved region, which an offscreen window does not have): the first CI run put Book's right page at x 475, inside
        // the injected 455 to 495 fold, which the simulator never does. The real-hinge gate keeps TT-0 (docs/fold-harness.md).
        if !r.foldCrossings.isEmpty {
            print("harness error: [info, not asserted] \(p.id) TT-0: frames cross the injected fold \(String(describing: r.division)): \(r.foldCrossings.map(HarnessRules.brief))")
        }
        if !r.navigationBandFrames.isEmpty {
            print("harness error: [info, not asserted] \(p.id) G-4: navigation-bar band frames not asserted offscreen: \(r.navigationBandFrames.map(HarnessRules.brief))")
        }
        // Tabletop's rail and pages are placed by the system's ArrangementView at the window's real reserved region. Offscreen
        // the harness laid the rail out as a horizontal row at y 335 and 393, across the fold, where the Duo has a vertical
        // column at x 619 (Mac calibration, 55240fc). So G-4 for Tabletop is reported here and asserted by the real-hinge gate.
        if p.id == "tabletop" {
            if !r.aboveTheFold.isEmpty {
                print("harness error: [info, not asserted] tabletop G-4: tappable frames above the fold offscreen: \(r.aboveTheFold.map(HarnessRules.brief))")
            }
        } else {
            HarnessRules.require(r.aboveTheFold.isEmpty, "\(p.id) G-4: tappable frames above the Tabletop fold: \(r.aboveTheFold.map(HarnessRules.brief))")
        }
        HarnessRules.checkDeck(r, maxFraction: p.id == "tabletop" ? nil : 0.5)
        if p.id == "closed" || p.id == "open" { HarnessRules.checkDeck(r, maxFraction: 0.38) }
        if p.expected != .tabletop { HarnessRules.checkLibraryToolbar(r) }
    }

    // MARK: Accessibility text sizes (7fe84f4, AX3)

    @Test(arguments: ["closed", "open", "openPortrait"], [0, 1])
    func deckStaysBoundedAtAccessibilitySizes(_ id: String, _ sizeIndex: Int) async throws {
        let p = HarnessPose.named(id)
        let size: UIContentSizeCategory = sizeIndex == 0 ? .accessibilityExtraLarge : .accessibilityExtraExtraExtraLarge
        let r = try #require(await FoldHost.render(p, type: size))
        defer { FoldHost.dispose(r) }
        HarnessRules.checkDeck(r, maxFraction: 0.5)
    }
}

/// The frame rules, shared by the harness tests and (later) by sim-side captures.
@MainActor
enum HarnessRules {
    /// One-line failures that say "failed", so the CI log's grep shows them (and so a reader sees the numbers).
    static func require(_ ok: Bool, _ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
        if !ok { fail(message, sourceLocation: sourceLocation) }
    }
    /// Also printed with "error:" so the CI step's grep shows it (Swift Testing's own issue lines are not matched).
    static func fail(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
        print("harness error: \(message)")
        Issue.record("harness failed: \(message)", sourceLocation: sourceLocation)
    }
    static func brief(_ r: CGRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))" }
    /// The deck is at most `maxFraction` of the container height, plus 12 pt of slack (the same slack as the UI test).
    static func checkDeck(_ r: Rendered, maxFraction: CGFloat?, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let maxFraction else { return }
        guard let deck = r.named["latestDeck"] else {
            fail("\(r.pose.id): the Latest updates deck was not on screen", sourceLocation: sourceLocation)
            return
        }
        let limit = r.pose.container.height * maxFraction + 12
        let message = "\(r.pose.id) J-5: deck \(Int(deck.width)) x \(Int(deck.height)) pt is over \(Int(limit)) pt"
        if r.pose.inferred {
            if deck.height > limit { print("harness error: [info, not asserted, insets inferred] \(message)") }
        } else {
            require(deck.height <= limit, message, sourceLocation: sourceLocation)
        }
    }

    /// TB-1, reported and not asserted. The first CI runs showed an offscreen window does not reproduce UIKit's toolbar:
    /// Closed drew bar buttons without accessibility labels, and Open, Open portrait and Book drew none, where the Duo
    /// simulator shows Settings and Add in every pose (UI test, 780c25a). So the toolbar stays a simulator check
    /// (PlayscribeUITests, gate.sh), and this prints what UIKit drew so calibration can revisit it.
    static func checkLibraryToolbar(_ r: Rendered) {
        let settings = r.uikitControl(identifier: "settingsButton"), add = r.uikitControl(label: "Add game")
        if settings == nil || add == nil {
            print("harness error: [info, not asserted] \(r.pose.id) TB-1: toolbar not reproduced offscreen. UIKit drew: \(r.topInventory)")
        }
    }
}
