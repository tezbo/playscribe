import Foundation
import Testing
@testable import Playscribe

/// 0.5.7 gate, Mac walk on main 74b15ab (step 5, "pose mid-flow"): Cyberpunk's Update 2.5 held through Open landscape, Book and
/// Tabletop, but back in Closed the game page's list showed instead. Every pose shows the same content: an update pushed in one
/// column, moved onto the Page by folding, is pushed again when the reader is back in one column (J-1, T-5).
@MainActor
struct PoseMidFlowTests {
    private func model() -> AppModel {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "midflow-\(UUID().uuidString).json"))
        m.livePose = .closed
        return m
    }

    /// The bundled game with the longest PS5 history (the walk used Cyberpunk, which comes from the live feed), in the library.
    private func history(_ m: AppModel) throws -> [Release] {
        let id = try #require(m.games.keys.sorted()
            .filter { m.ps5Releases($0).count >= 2 }
            .max { m.ps5Releases($0).count < m.ps5Releases($1).count }, "no bundled game has two PS5 updates")
        if m.entry(id) == nil, let g = m.game(id) { m.addGame(g, status: .owned) }
        return m.ps5Releases(id)
    }

    /// The Updates tab push (the walk's path): Closed, then Book or Tabletop, then Closed again.
    @Test func anUpdatesTabPushSurvivesAFoldAndBack() throws {
        let m = model()
        let r = try history(m)[0]
        m.nav.tab = .updates
        m.openFromUpdates(r)
        #expect(m.nav.updatesRelease == ReleaseRef(gameID: r.gameID, releaseID: r.id))

        m.livePose = .tabletop
        m.leaveOneColumn()
        #expect(m.nav.tab == .library)
        #expect(m.nav.gameID == r.gameID)
        #expect(m.selectedRelease(r.gameID)?.id == r.id, "Book and Tabletop show the update on the Page")

        m.livePose = .closed
        m.enterOneColumn()
        #expect(m.isViewing(r.gameID, r.id), "back in Closed the same update shows, not the game page's list")
        #expect(m.nav.tab == .updates && m.nav.updatesRelease == ReleaseRef(gameID: r.gameID, releaseID: r.id),
                "and it is the Updates tab's push again, so Back returns to the Updates list")
    }

    /// The Library push: an All updates row in Closed, then a fold and back.
    @Test func aLibraryPushSurvivesAFoldAndBack() throws {
        let m = model()
        let rs = try history(m)
        let r = rs[1]
        m.openGame(r.gameID, chapter: .updates)
        m.listTap(r.gameID, releaseID: r.id, pushes: true)
        #expect(m.nav.detailReleaseID == r.id)

        m.livePose = .book
        m.leaveOneColumn()
        #expect(m.nav.detailReleaseID == nil)
        #expect(m.selectedRelease(r.gameID)?.id == r.id)

        m.livePose = .closed
        m.enterOneColumn()
        #expect(m.nav.detailReleaseID == r.id, "back in Closed the pushed update shows again")
    }

    /// What the reader did in Book or Tabletop wins: another pick, another section or Back drops the old push.
    @Test func aPickInBookIsNotUndoneByFoldingBack() throws {
        let m = model()
        let rs = try history(m)
        m.openGame(rs[0].gameID, chapter: .updates)
        m.listTap(rs[0].gameID, releaseID: rs[1].id, pushes: true)
        m.livePose = .book
        m.leaveOneColumn()
        m.nav.chapter = .news
        m.livePose = .closed
        m.enterOneColumn()
        #expect(m.nav.detailReleaseID == nil, "the reader moved to News in Book; Closed shows News, not the old update")

        m.livePose = .book
        m.leaveOneColumn()
        m.closeGame()
        m.livePose = .closed
        m.enterOneColumn()
        #expect(m.nav.gameID == nil && m.nav.detailReleaseID == nil && m.nav.updatesRelease == nil, "Back in Book stays Back")
    }
}
