import Foundation
import Testing
@testable import Playscribe

/// Upcoming grid fills the width in every pose: no dead strip on the trailing side.
@MainActor
struct UpcomingFitTests {
    @Test func columnsAlwaysFillTheWidth() {
        for w in stride(from: CGFloat(220), through: 900, by: 7) {
            let f = UpcomingView.fit(width: w)
            let used = CGFloat(f.count) * f.size + CGFloat(f.count - 1) * 10
            #expect(used <= w)
            #expect(w - used < CGFloat(f.count) * 0.01 + 0.01)
            if w >= 238 { #expect(f.size >= 104) }
        }
    }

    @Test func wideContainersAddColumnsInsteadOfCappingTileSize() {
        #expect(UpcomingView.fit(width: 700).count >= 5)
        #expect(UpcomingView.fit(width: 700).size < 160)
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
