import Foundation
import Testing
@testable import Playscribe

/// Upcoming games that share a release date keep one order from launch to launch (bug-upcoming-same-date-order, caught by the
/// screen diffs on #485): by date, then by name, then by id, whatever order they arrive in.
struct UpcomingOrderTests {
    private func game(_ id: String, _ name: String, _ date: String?) -> CatalogGame {
        CatalogGame(id: id, name: name, platforms: [.ps5], releaseDate: date, releasePrecision: date == nil ? .tbd : .day, coverage: .none)
    }

    private var games: [CatalogGame] {
        [game("c", "Cronos", "2026-12-04"), game("a", "astro rally", "2026-12-04"), game("b", "Big Game", "2026-12-04"),
         game("e", "Earlier", "2026-11-20"), game("t", "Undated", nil), game("d2", "Big Game", "2026-12-04")]
    }

    @Test func sameDateGamesSortByNameThenID() {
        let expected = ["e", "a", "b", "d2", "c", "t"]
        for seed in 0..<50 {
            var rng = SeededRandom(seed: UInt64(seed))
            let shuffled = games.shuffled(using: &rng)
            #expect(shuffled.sorted(by: CatalogGame.upcomingOrder).map(\.id) == expected)
        }
    }

    private struct SeededRandom: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}
