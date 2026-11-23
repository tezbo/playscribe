import CoreGraphics
import SwiftUI
import Testing
@testable import Playscribe

/// 6b intro tour (handoff/0.6.0-intro-tour.md): copy, step order and where the card goes in each pose.
@MainActor
struct IntroTourTests {
    @Test func threeStepsInOrderWithTheSpecCopy() {
        #expect(TourStep.allCases.map(\.title) == ["Open a game", "Everything new", "Spoiler-safe"])
        #expect(TourStep.openGame.counter == "1 of 3")
        #expect(TourStep.updates.primary == "Next")
        #expect(TourStep.spoiler.primary == "Done")
        #expect(TourStep.spoiler.next == nil)
        #expect(TourStep.openGame.body(emptyLibrary: true).hasSuffix("Opening one does not add it to your Library."))
        #expect(TourStep.updates.body(emptyLibrary: true).hasSuffix("Add games and they appear here."))
        #expect(TourStep.openGame.announcement(emptyLibrary: false)
                == "Tour, step 1 of 3. Open a game. Tap any game to read its latest update.")
        // V-3 and copy rules: no source names, no ellipsis, no dot separators.
        for s in TourStep.allCases {
            for text in [s.title, s.body(emptyLibrary: true), s.body(emptyLibrary: false)] {
                #expect(!text.unicodeScalars.contains { $0.value == 0x2026 || $0.value == 0xB7 })
            }
        }
    }

    @Test func theFirstCandidateOnScreenIsTheTarget() {
        let size = CGSize(width: 466, height: 678)
        let tiles = [CGRect(x: 130, y: 300, width: 100, height: 133), CGRect(x: 16, y: 300, width: 100, height: 133),
                     CGRect(x: 16, y: -200, width: 100, height: 133)]
        #expect(TourLayout.target(tiles, container: size, pose: .closed, division: nil)?.minX == 16)
        #expect(TourLayout.target(tiles, container: size, pose: .closed, division: nil)?.minY == 300)
        // Tabletop: nothing above the fold is pointed at.
        let fold = CGRect(x: 0, y: 374, width: 466, height: 40)
        #expect(TourLayout.target(tiles, container: size, pose: .tabletop, division: fold) == nil)
        #expect(TourLayout.target([CGRect(x: 16, y: 450, width: 44, height: 44)], container: size, pose: .tabletop, division: fold) != nil)
        // A tile whose labels run past the bottom edge is still pointed at (Open portrait, c73186d2); one barely showing is not.
        #expect(TourLayout.target([CGRect(x: 16, y: 600, width: 147, height: 243)], container: size, pose: .closed, division: nil) != nil)
        #expect(TourLayout.target([CGRect(x: 16, y: 660, width: 147, height: 243)], container: size, pose: .closed, division: nil) == nil)
    }

    @Test func tabletopCardSitsInTheLowerHalfClearOfTheRail() {
        let size = CGSize(width: 951, height: 678), fold = CGRect(x: 0, y: 374, width: 951, height: 40)
        let card = TourLayout.card(size: CGSize(width: 0, height: 150), target: nil, container: size, pose: .tabletop, division: fold,
                                   safeArea: EdgeInsets(), landscape: true, railWidth: 56)
        #expect(card.minY >= fold.maxY)
        #expect(card.maxY <= size.height)
        #expect(card.maxX <= size.width - 56)
        #expect(card.minX >= 16)
    }

    @Test func stepTwoSaysWhereItsTabIs() {
        #expect(TourStep.updates.place(onRail: false) == "Updates is in the bottom bar.")
        #expect(TourStep.updates.place(onRail: true) == "Updates is on the rail.")
        #expect(TourStep.openGame.place(onRail: false) == nil && TourStep.spoiler.place(onRail: true) == nil)
        #expect(TourStep.updates.announcement(emptyLibrary: false, onRail: true).hasSuffix("newest first. Updates is on the rail."))
    }

    @Test func tabletopCardNeverCoversItsTarget() {
        let size = CGSize(width: 951, height: 678), fold = CGRect(x: 0, y: 374, width: 951, height: 40)
        for tile in [CGRect(x: 16, y: 430, width: 100, height: 60), CGRect(x: 16, y: 560, width: 100, height: 100),
                     CGRect(x: 16, y: 420, width: 100, height: 240)] {
            let card = TourLayout.card(size: CGSize(width: 0, height: 100), target: tile, container: size, pose: .tabletop, division: fold,
                                       safeArea: EdgeInsets(), landscape: true, railWidth: 56)
            #expect(!card.intersects(tile))
            #expect(card.minY >= fold.maxY && card.maxY <= size.height && card.maxX <= size.width - 56)
        }
    }

    @Test func axLandscapeCardGoesWideButStaysOffTheSideTabBar() {
        let size = CGSize(width: 678, height: 466), lane = CGRect(x: 90, y: 0, width: 588, height: 466)
        let r = TourLayout.card(size: CGSize(width: 0, height: 400), target: nil, container: size, pose: .closed, division: nil,
                                safeArea: EdgeInsets(), landscape: true, railWidth: 0, wide: true, lane: lane)
        #expect(r.width >= TourLayout.wideFrom, "\(r)")
        #expect(r.minX >= lane.minX + 16 && r.maxX <= lane.maxX - 16, "\(r)")
        let narrow = TourLayout.card(size: CGSize(width: 0, height: 150), target: nil, container: size, pose: .closed, division: nil,
                                     safeArea: EdgeInsets(), landscape: true, railWidth: 0)
        #expect(narrow.width == TourLayout.maxWidth)
    }

    @Test func bookCardStaysOnTheTargetsPage() {
        let size = CGSize(width: 951, height: 678), fold = CGRect(x: 455.5, y: 0, width: 40, height: 678)
        let right = CGRect(x: 600, y: 100, width: 200, height: 44)
        let r = TourLayout.card(size: CGSize(width: 0, height: 140), target: right, container: size, pose: .book, division: fold,
                                safeArea: EdgeInsets(), landscape: true, railWidth: 0)
        #expect(r.minX >= fold.maxX + 24)
        #expect(r.width <= 320)
        let left = CGRect(x: 40, y: 100, width: 100, height: 133)
        let l = TourLayout.card(size: CGSize(width: 0, height: 140), target: left, container: size, pose: .book, division: fold,
                                safeArea: EdgeInsets(), landscape: true, railWidth: 0)
        #expect(l.maxX <= fold.minX - 24)
    }

    @Test func cardGoesBelowTheTargetThenAboveThenTop() {
        let size = CGSize(width: 466, height: 678), card = CGSize(width: 0, height: 150)
        let high = TourLayout.card(size: card, target: CGRect(x: 16, y: 120, width: 100, height: 133), container: size, pose: .closed,
                                   division: nil, safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0), landscape: false, railWidth: 0)
        #expect(high.minY == CGFloat(120 + 133) + TourLayout.gap, "\(high)")
        let low = TourLayout.card(size: card, target: CGRect(x: 16, y: 450, width: 100, height: 133), container: size, pose: .closed,
                                  division: nil, safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0), landscape: false, railWidth: 0)
        #expect(low.maxY == CGFloat(450) - TourLayout.gap, "\(low)")
        // The text-only card (no target) sits above the tab bar, never under it.
        let none = TourLayout.card(size: card, target: nil, container: size, pose: .closed, division: nil,
                                   safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0), landscape: false, railWidth: 0)
        #expect(none.maxY <= size.height - 96)
        #expect(none.minX >= 16 && none.maxX <= size.width - 16)
    }
}
