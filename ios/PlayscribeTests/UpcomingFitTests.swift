import Foundation
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
