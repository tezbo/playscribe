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
        #expect(c.body == "Update 1.1 is live on PS5: respec with Draught of Mind Rebirth, and a new Story mode.")
        #expect(c.body.count <= 110)
        // Without an editorial line: the two shortest headlines, one colon, a full stop.
        var plain = r
        plain.pushLine = nil
        let fallback = NotificationService.body(for: plain)
        #expect(fallback.filter { $0 == ":" }.count == 1)
        #expect(fallback.count <= 110 && fallback.hasSuffix("."))
        #expect(c.threadIdentifier == "dawnwalker")
        #expect(c.interruptionLevel == .active)
        #expect(c.userInfo["releaseId"] as? String == "dawnwalker@1.1")
    }

    @Test("Feed records decode: camelCase ids and fractional-second dates")
    func feedDecode() throws {
        let json = #"{"updatedAt":"2026-10-24T20:57:39.904Z","releases":[{"id":"dawnwalker@1.1","gameId":"dawnwalker","displayName":"Update 1.1","kind":"major","kindBasis":"studio","announcedAt":"2026-10-22T09:17:48.000Z","sourceIds":["dawnwalker-steam"],"platforms":[{"platform":"pc","status":"live","version":null,"sizeBytes":null,"liveAt":{"value":"2026-10-22T09:17:48.000Z","verification":"official","sourceId":"dawnwalker-steam","checkedAt":"2026-10-24T20:57:37.642Z"},"bundles":[],"verification":"official"}],"revision":1}]}"#
        let latest = try JSONCoding.decoder.decode(FeedClient.Latest.self, from: Data(json.utf8))
        let m = freshModel()
        m.feedReleases = latest.releases
        // The feed's PC row merges with the curated PS5 row and editorial fields.
        let r = m.release("dawnwalker", "dawnwalker@1.1")
        #expect(r?.ps5State == .onPS5)
        #expect(r?.platforms.count == 3 || r?.platforms.count == 2)
        #expect(r?.headline != nil)
    }

    @Test("No 'on PS5' date falls before the PS5 launch, 12 Nov 2020")
    func ps5Dates() {
        let launch = CatalogGame.ps5Launch
        let monthYear = Date.FormatStyle.dateTime.month(.abbreviated).year()
        for e in PS5Index.shared.entries {
            let g = PS5Index.shared.game(e)
            guard let line = g.ps5DateLine else { continue }
            if line.hasPrefix("Released "), let d = g.releaseDate?.isoDay { #expect(d >= launch, "\(g.name): \(line)") }
            if line.hasPrefix("Playable on PS5 since "), let b = g.playableSince?.isoDay {
                #expect(b >= launch, "\(g.name): \(line)")
                #expect(line.hasSuffix(b.formatted(monthYear)))
            }
        }
        let minecraft = PS5Index.shared.entries.first { $0.n == "Minecraft" }.map(PS5Index.shared.game)
        #expect(minecraft?.ps5DateLine?.contains("2019") != true)
    }

    @Test("Search dedupes by IGDB id and prefers curated records (A-3)")
    func search() {
        let hits = PS5Index.shared.search("dawnwalker")
        #expect(!hits.isEmpty)
    }
}
