import Foundation
import SwiftUI
import Testing
@testable import Playscribe

/// Upcoming grid fills the width in every pose: no dead strip on the trailing side.
@MainActor
struct UpcomingFitTests {
    @Test func tilesStayBetween120And168WithSixteenGaps() {
        for w in stride(from: CGFloat(420), through: 1200, by: 7) {
            let f = UpcomingView.fit(width: w)
            let used = CGFloat(f.count) * f.size + CGFloat(f.count - 1) * 16
            #expect(used <= w)
            #expect(f.size >= 120 && f.size <= 168)
            #expect(f.count >= 3)
        }
    }

    @Test func openLandscapeGivesAboutSixColumns() {
        // ~875 pt of content beside the rail.
        #expect((5...7).contains(UpcomingView.fit(width: 875).count))
    }

    @Test func narrowWidthKeepsThreeColumns() {
        #expect(UpcomingView.fit(width: 300).count == 3)
    }
}

@MainActor
struct UpcomingBookSplitTests {
    @Test func bookSplitNeverLosesOrDuplicatesATile() {
        for n in 0...40 { for l in 2...4 { for r in 2...4 {
            let k = UpcomingView.leftCount(of: n, leftColumns: l, rightColumns: r)
            #expect(k >= 0 && k <= n)
        } } }
    }

    @Test func bookSplitIsProportionalToColumns() {
        #expect(UpcomingView.leftCount(of: 6, leftColumns: 3, rightColumns: 3) == 3)
        #expect(UpcomingView.leftCount(of: 5, leftColumns: 2, rightColumns: 3) == 2)
        #expect(UpcomingView.leftCount(of: 1, leftColumns: 2, rightColumns: 2) == 1)
    }
}

@MainActor
struct UpcomingBookTileSizeTests {
    @Test func bothPagesShareTheSmallerTileSize() {
        for (l, r) in [(CGFloat(380), CGFloat(420)), (500, 380), (400, 400), (300, 760)] {
            let f = UpcomingView.bookFits(leftWidth: l, rightWidth: r)
            #expect(f.left.size == f.right.size)
            #expect(f.left.size == min(UpcomingView.fit(width: l).size, UpcomingView.fit(width: r).size))
            // Never wider than the page it sits on.
            #expect(CGFloat(f.left.count) * f.left.size + CGFloat(f.left.count - 1) * UpcomingView.gap <= l + 0.01)
            #expect(CGFloat(f.right.count) * f.right.size + CGFloat(f.right.count - 1) * UpcomingView.gap <= r + 0.01)
        }
    }
}

/// Upcoming at accessibility sizes: AX3 and up switch to one-column rows (Iris's option b); below that the #287 columns stay.
@MainActor
struct UpcomingRowSwitchTests {
    @Test func rowsFromAX3Only() {
        #expect(!UpcomingView.usesRows(.xxxLarge))
        #expect(!UpcomingView.usesRows(.accessibility2))
        #expect(UpcomingView.usesRows(.accessibility3))
        #expect(UpcomingView.usesRows(.accessibility5))
    }
}

/// Short Upcoming sections share a row in Open and Tabletop instead of leaving it half empty.
@MainActor
struct UpcomingPackedBlockTests {
    @Test func blockIsAsWideAsItsTilesNeverWiderThanTheRow() {
        #expect(UpcomingView.blockColumns(games: 3, available: 6) == 3)
        #expect(UpcomingView.blockColumns(games: 2, available: 6) == 2)
        #expect(UpcomingView.blockColumns(games: 20, available: 6) == 6)
        #expect(UpcomingView.blockColumns(games: 0, available: 5) == 1)
    }

    @Test func threeAndTwoShareOneRowFromFiveColumns() {
        // Blocks of 3 and 2 tiles plus one gap equal exactly 5 columns.
        for w in stride(from: CGFloat(700), through: 1200, by: 11) {
            let f = UpcomingView.fit(width: w)
            guard f.count >= 5 else { continue }
            let a = CGFloat(3) * f.size + 2 * UpcomingView.gap, b = CGFloat(2) * f.size + UpcomingView.gap
            #expect(a + UpcomingView.gap + b <= w)
        }
    }
}
