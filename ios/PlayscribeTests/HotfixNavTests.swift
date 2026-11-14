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

    private func gameWithHistory(_ m: AppModel) throws -> (id: String, newest: Release, older: Release) {
        let entry = try #require(m.data.collection.first { m.ps5Releases($0.gameID).count >= 3 })
        let all = m.ps5Releases(entry.gameID)
        return (entry.gameID, all[0], all[2])
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
