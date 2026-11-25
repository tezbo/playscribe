import Foundation
import Testing
@testable import Playscribe

/// bug-072 (Terry, 25 Nov: Control Resonant opened on its Gallery from an earlier session): opening a game always lands on its
/// newest update (R-1), whatever section it was left on, in this launch or an earlier one. Back within a visit still returns to
/// the section the reader was on (bug-070).
@MainActor
struct GameOpensOnNewestTests {
    private func url() -> URL { URL.temporaryDirectory.appending(path: "opens-newest-\(UUID().uuidString).json") }
    private let game = "dawnwalker"
    private func seeded(_ u: URL) -> AppModel {
        let m = AppModel(storeURL: u)
        if m.data.collection.isEmpty { m.data = PersistedState(collection: Fixtures.shared.seedCollection) }
        return m
    }

    @Test func openingAfterRelaunchLandsOnTheNewestUpdate() throws {
        let u = url()
        let first = seeded(u)
        first.openGame(game)
        first.nav.chapter = .gallery
        first.closeGame()
        first.saveNow()
        let second = AppModel(storeURL: u)
        second.openGame(game)
        #expect(second.nav.chapter == .updates)
    }

    @Test func relaunchOnAnOpenGameResumesOnTheUpdatesSection() throws {
        let u = url()
        let first = seeded(u)
        first.openGame(game)
        first.nav.chapter = .gallery
        first.saveNow()
        let second = AppModel(storeURL: u)
        #expect(second.nav.chapter == .updates)
    }

    @Test func reopeningInTheSameLaunchLandsOnTheNewestUpdate() {
        let m = seeded(url())
        m.openGame(game)
        m.nav.chapter = .gallery
        m.closeGame()
        m.openGame(game)
        #expect(m.nav.chapter == .updates)
    }

    @Test func backFromASecondGameReturnsToTheSectionItWasLeftOn() throws {
        let m = seeded(url())
        let other = try #require(m.data.collection.map(\.gameID).first { $0 != game })
        m.openGame(game)
        m.nav.chapter = .gallery
        m.openGame(other)
        m.closeGame()
        #expect(m.nav.gameID == game)
        #expect(m.nav.chapter == .gallery)
    }
}
