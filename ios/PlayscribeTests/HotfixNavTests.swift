import Foundation
import Testing
@testable import Playscribe

/// 0.5.6 hotfix (Terry's Duo test, 14 Nov). Opening a game lands on its newest update (R-1), not an update picked on an
/// earlier visit (he tapped Cyberpunk and got Patch 2.31, not Update 2.5). A row tap where the release is pushed (Closed,
/// open portrait) does not change the page underneath, so Back returns to the update he was reading (J-1).
@MainActor
struct HotfixNavTests {
    private func model() -> AppModel {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "hotfix-\(UUID().uuidString).json"))
        m.resetDemo()
        return m
    }

    /// The bundled game with the longest PS5 history (at least two updates), added to the library if the demo lacks it.
    private func gameWithHistory(_ m: AppModel) throws -> (id: String, newest: Release, older: Release) {
        let id = try #require(m.games.keys.sorted()
            .filter { m.ps5Releases($0).count >= 2 }
            .max { m.ps5Releases($0).count < m.ps5Releases($1).count }, "no bundled game has two PS5 updates")
        if m.entry(id) == nil, let g = m.game(id) { m.addGame(g, status: .owned) }
        let all = m.ps5Releases(id)
        return (id, all[0], all[all.count - 1])
    }

    @Test("R-1: reopening a game shows its newest update, not one picked on an earlier visit")
    func reopenLandsOnNewest() throws {
        let m = model()
        let g = try gameWithHistory(m)
        m.openGame(g.id)
        m.select(g.id, releaseID: g.older.id)
        m.closeGame()
        m.openGame(g.id)
        #expect(m.selectedRelease(g.id)?.id == g.newest.id)
    }

    @Test("J-1: a pushed release leaves the page underneath alone, so Back returns to it")
    func pushKeepsThePageUnderneath() throws {
        let m = model()
        let g = try gameWithHistory(m)
        m.openGame(g.id)
        #expect(m.selectedRelease(g.id)?.id == g.newest.id)
        m.listTap(g.id, releaseID: g.older.id, pushes: true)
        #expect(m.nav.detailReleaseID == g.older.id)
        #expect(!m.isUnread(g.older))
        // Back (the stack pops the pushed release).
        m.nav.detailReleaseID = nil
        #expect(m.selectedRelease(g.id)?.id == g.newest.id)
    }

    @Test("J-1: side by side, a row tap shows the release on the Page in place")
    func sideBySideSelects() throws {
        let m = model()
        let g = try gameWithHistory(m)
        m.openGame(g.id)
        m.listTap(g.id, releaseID: g.older.id, pushes: false)
        #expect(m.nav.detailReleaseID == nil)
        #expect(m.selectedRelease(g.id)?.id == g.older.id)
    }
}
