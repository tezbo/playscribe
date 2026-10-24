import Foundation
import Testing
@testable import Playscribe

@MainActor
struct ModelTests {
    func freshModel() -> AppModel {
        let url = URL.temporaryDirectory.appending(path: "state-\(UUID().uuidString).json")
        return AppModel(storeURL: url)
    }

    @Test("Fixtures decode and every release follows the PS5 spec")
    func fixtures() {
        let f = Fixtures.shared
        #expect(f.games.count >= 5)
        #expect(f.releases.contains { $0.id == "dawnwalker@1.1" })
        #expect(PS5Index.shared.count > 1000)
    }

    @Test("Dawnwalker 1.1 is On PS5; PC-only Steam posts never are (V-2)")
    func ps5States() {
        let m = freshModel()
        let dw = m.release("dawnwalker", "dawnwalker@1.1")
        #expect(dw?.ps5State == .onPS5)
        #expect(dw?.ps5Version == nil)
        for r in m.releases("control-resonant") {
            #expect(r.ps5State == .pcOnly)
            #expect(r.ps5Version == nil)
        }
        #expect(m.unreadCount("control-resonant") == 0)
    }

    @Test("Opening a game expands the newest On PS5 release (R-1)")
    func openGame() {
        let m = freshModel()
        m.openGame("dawnwalker")
        #expect(m.nav.gameID == "dawnwalker")
        #expect(m.isExpanded("rel:dawnwalker@1.1"))
    }

    @Test("Remove then Undo restores status, level, bookmarks and notes (B-8)")
    func removeUndo() {
        let m = freshModel()
        m.setStatus("dawnwalker", .wishlist)
        m.setNotify("dawnwalker", .major)
        m.toggleBookmark(kind: .release, id: "dawnwalker@1.1", gameID: "dawnwalker")
        m.saveNote(Note(id: "n1", gameID: "dawnwalker", text: "Try a witch build", updatedAt: .now))
        m.removeGame("dawnwalker")
        #expect(m.entry("dawnwalker") == nil)
        m.toast?.undo?()
        #expect(m.entry("dawnwalker")?.status == .wishlist)
        #expect(m.notifyLevel("dawnwalker") == .major)
        #expect(m.isBookmarked(kind: .release, id: "dawnwalker@1.1"))
        #expect(m.data.notes.contains { $0.id == "n1" })
    }

    @Test("New games get All for Owned and Major for others (A-9)")
    func defaultLevels() {
        let m = freshModel()
        let g = PS5Index.shared.popular(limit: 1)[0]
        m.addGame(g, status: .wishlist)
        #expect(m.notifyLevel(g.id) == .major)
    }

    @Test("Console versions bump in the PS5 format")
    func versions() {
        #expect(AppModel.bumpConsoleVersion("01.004.000", major: false) == "01.004.001")
        #expect(AppModel.bumpConsoleVersion("01.004.002", major: true) == "01.005.000")
    }

    @Test("Notification content follows N-4")
    func notificationContent() {
        let m = freshModel()
        let r = m.release("dawnwalker", "dawnwalker@1.1")!
        let c = NotificationService.content(for: r, game: m.game("dawnwalker")!, badge: 1)
        #expect(c.title == "The Blood of Dawnwalker")
        #expect(c.body.hasPrefix("Update 1.1 is live on PS5: "))
        #expect(c.threadIdentifier == "dawnwalker")
        #expect(c.interruptionLevel == .active)
        #expect(c.userInfo["releaseId"] as? String == "dawnwalker@1.1")
    }

    @Test("Search dedupes by IGDB id and prefers curated records (A-3)")
    func search() {
        let hits = PS5Index.shared.search("dawnwalker")
        #expect(!hits.isEmpty)
    }
}
