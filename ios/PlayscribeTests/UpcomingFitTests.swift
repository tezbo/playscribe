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
