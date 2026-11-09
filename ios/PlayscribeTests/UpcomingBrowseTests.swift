import Foundation
import Testing
@testable import Playscribe

/// Tapping a game in Library > Upcoming only opens it; it must not file it as Wishlist.
@MainActor
struct UpcomingBrowseTests {
    private func model() -> AppModel {
        AppModel(storeURL: URL.temporaryDirectory.appending(path: "browse-\(UUID().uuidString).json"))
    }

    /// A feed-style game that is in neither the fixtures nor the library.
    private var feedGame: CatalogGame {
        CatalogGame(id: "igdb-999001", name: "Feed Only", platforms: [.ps5], releaseDate: "2099-01-01",
                    releasePrecision: .day, igdbID: 999001, coverage: .none)
    }

    @Test func openingAnUpcomingGameDoesNotAddItToTheLibrary() {
        let m = model()
        let g = feedGame
        #expect(m.entry(g.id) == nil)
        #expect(m.game(g.id) == nil)
        let before = m.data.collection.count
        m.browseGame(g)
        #expect(m.data.collection.count == before)
        #expect(m.entry(g.id) == nil)
        #expect(!m.data.customGames.contains { $0.id == g.id })
    }

    @Test func gamePageStillResolvesForAnUnfiledGame() {
        let m = model()
        let g = feedGame
        m.browseGame(g)
        #expect(m.nav.gameID == g.id)
        #expect(m.nav.tab == .library)
        #expect(m.game(m.nav.gameID ?? "")?.name == "Feed Only")
    }

    @Test func browsingIsNeverSaved() throws {
        let url = URL.temporaryDirectory.appending(path: "browse-\(UUID().uuidString).json")
        let m = AppModel(storeURL: url)
        m.browseGame(feedGame)
        let reopened = AppModel(storeURL: url)
        #expect(reopened.game("igdb-999001") == nil)
        #expect(reopened.data.collection.isEmpty)
    }

    @Test func watchingAfterBrowsingFilesItOnceAsWishlist() {
        let m = model()
        let g = feedGame
        m.browseGame(g)
        m.addGame(g, status: .wishlist)
        #expect(m.data.collection.filter { $0.gameID == g.id }.count == 1)
        #expect(m.entry(g.id)?.status == .wishlist)
        #expect(m.game(g.id) != nil)
    }

    @Test func openingAGameAlreadyInTheLibraryKeepsItsStatus() {
        let m = model()
        let g = feedGame
        m.addGame(g, status: .wishlist)
        m.setStatus(g.id, .watching)
        m.browseGame(g)
        #expect(m.entry(g.id)?.status == .watching)
        #expect(m.browsedGames[g.id] == nil)
    }

    // r053-tap-opens-tick-adds (Iris): the first-run "Popular on PS5" covers. A tap opens the game; the tick adds it, once.
    @Test func tappingAFirstRunCoverOpensTheGameAndLeavesTheLibraryUnchanged() {
        let m = model()
        let g = feedGame
        let before = m.data.collection.count
        m.browseGame(g)                          // what PopularCover's cover button calls
        #expect(m.nav.gameID == g.id)
        #expect(m.data.collection.count == before)
        #expect(m.entry(g.id) == nil)
    }

    @Test func tickingACoverAddsTheGameExactlyOnceAndAnUpcomingOneAsWishlist() {
        let m = model()
        let g = feedGame
        let before = m.data.collection.count
        m.addGame(g, status: .owned)             // what PopularCover's tick calls
        m.addGame(g, status: .owned)             // a second tick (or a double tap) is a no-op
        #expect(m.data.collection.count == before + 1)
        #expect(m.entry(g.id)?.status == .wishlist)
    }
}
