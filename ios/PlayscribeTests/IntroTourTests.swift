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
                #expect(!text.contains("…") && !text.contains("·"))
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
        #expect(high.minY == 120 + 133 + 12)
        let low = TourLayout.card(size: card, target: CGRect(x: 16, y: 450, width: 100, height: 133), container: size, pose: .closed,
                                  division: nil, safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0), landscape: false, railWidth: 0)
        #expect(low.maxY == 450 - 12)
        // The text-only card (no target) sits above the tab bar, never under it.
        let none = TourLayout.card(size: card, target: nil, container: size, pose: .closed, division: nil,
                                   safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0), landscape: false, railWidth: 0)
        #expect(none.maxY <= size.height - 96)
        #expect(none.minX >= 16 && none.maxX <= size.width - 16)
    }
}
