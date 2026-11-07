import Foundation
import Testing
@testable import Playscribe

/// Library > Upcoming: games filed as Watching appear on the watchlist beside Wishlist ones.
@MainActor
struct UpcomingWatchlistTests {
    @Test func watchedUpcomingIncludesWishlistAndWatching() {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "watch-\(UUID().uuidString).json"))
        func g(_ n: Int) -> CatalogGame {
            CatalogGame(id: "igdb-9990\(n)", name: "G\(n)", platforms: [.ps5], releaseDate: "2099-01-0\(n)",
                        releasePrecision: .day, igdbID: 9990 + n, coverage: .none)
        }
        m.addGame(g(1), status: .wishlist)
        m.addGame(g(2), status: .watching)
        let ids = m.upcomingWatched.map(\.id)
        #expect(ids.contains("igdb-99901"))
        #expect(ids.contains("igdb-99902"))
    }
}
