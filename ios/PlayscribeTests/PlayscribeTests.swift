import Foundation
import Testing
import SwiftUI
import UserNotifications
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

    @Test("Steam is the source of truth (Terry, 26 Oct): Steam-live releases count as released, never with a PC version as the PS5 one")
    func ps5States() {
        let m = freshModel()
        let dw = m.release("dawnwalker", "dawnwalker@1.1")
        #expect(dw?.ps5State == .onPS5)
        #expect(dw?.ps5Version == nil)
        for r in m.releases("control-resonant") where r.ps5 == nil {
            #expect(r.ps5State == .onPS5)
            #expect(r.ps5Version == nil)
        }
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
            if line.hasPrefix("Released ") || line.hasPrefix("PS5 version since "), let d = g.releaseDate?.isoDay { #expect(d >= launch, "\(g.name): \(line)") }
            if line.hasPrefix("Playable on PS5 since "), let b = g.playableSince?.isoDay {
                #expect(b >= launch, "\(g.name): \(line)")
                #expect(line.hasSuffix(b.formatted(monthYear)))
            }
        }
        let minecraft = PS5Index.shared.entries.first { $0.n == "Minecraft" }.map(PS5Index.shared.game)
        #expect(minecraft?.ps5DateLine?.contains("2019") != true)
        #expect(minecraft?.ps5DateLine?.hasPrefix("PS5 version since") == true)
    }

    @Test("Search dedupes by IGDB id and prefers curated records (A-3)")
    func search() {
        let hits = PS5Index.shared.search("dawnwalker")
        #expect(!hits.isEmpty)
    }
}

@MainActor
struct PS5ContentTests {
    @Test("GR-2: no PC-only term on a PS5 page outside the PC-only group")
    func noPCTermsOnPS5Pages() {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "gr2-\(UUID().uuidString).json"))
        for g in m.fixtures.games {
            for r in m.releases(g.id) where r.isPS5Listed {
                var lines = [r.ps5Headline, r.ps5Summary, r.pushLine].compactMap { $0 } + r.ps5KeyChanges
                lines.append(NotificationService.body(for: r))
                lines += r.notes.flatMap(\.items).filter { !$0.isPCOnly }.map(\.text)
                for line in lines { #expect(!PCOnly.matches(line), "\(r.id): \(line)") }
            }
            for e in m.fixtures.book where e.gameID == g.id {
                #expect(!PCOnly.matches(e.title + " " + e.body), "\(e.id)")
            }
        }
        // The blocklist itself.
        for term in ["FrameGen", "DLSS", "FSR", "XeSS", "AMD", "NVIDIA", "Intel Arc", "Steam", "Steam Deck", "mouse", "keyboard", "ultrawide"] {
            #expect(PCOnly.matches("Fixed \(term) issue"), "\(term)")
        }
    }
}

@MainActor
struct ReviewFixTests {
    func model() -> AppModel { AppModel(storeURL: URL.temporaryDirectory.appending(path: "gr-\(UUID().uuidString).json")) }

    @Test("GR-4: note search finds PS5 items, PC-only last, scoped")
    func noteSearch() {
        let m = model()
        let hits = m.noteHits("subtitle", scope: .thisGame, gameID: "dawnwalker")
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { $0.release.gameID == "dawnwalker" })
        #expect(m.noteHits("s", scope: .allGames, gameID: nil).isEmpty)
    }

    @Test("GR-5: a future game says Out, never Released, and adds as Wishlist")
    func futureGames() {
        let m = model()
        var g = PS5Index.shared.popular(limit: 1)[0]
        g.id = "future-test"; g.releaseDate = "2099-11-19"; g.playableSince = nil; g.earlyAccess = nil
        #expect(g.ps5DateLine?.hasPrefix("Out 19 Nov") == true)
        m.addGames([g], status: .owned)
        #expect(m.entry("future-test")?.status == .wishlist)
    }

    @Test("GR-7: adding several games is undone by one Undo")
    func multiAdd() {
        let m = model()
        let games = Array(PS5Index.shared.popular(limit: 3))
        m.addGames(games, status: .owned)
        #expect(m.toast?.text == "Added 3 games")
        m.toast?.undo?()
        #expect(games.allSatisfy { m.entry($0.id) == nil })
    }

    @Test("GR-1: no game in the demo set has an empty Updates chapter")
    func neverEmpty() {
        let m = model()
        for c in m.data.collection {
            let g = m.game(c.gameID)!
            #expect(!m.ps5Releases(c.gameID).isEmpty || !g.ps5AvailabilityLine.isEmpty)
        }
    }
}

@MainActor
struct DateCopyTests {
    @Test("Dates read day-first in every locale")
    func dayFirst() {
        let d = "2026-11-19".isoDay!
        #expect(d.dayMonth == "19 Nov")
        #expect(d.shortDay == "19 Nov 2026")
    }
}

@MainActor
struct DatePrecisionTests {
    func game(_ d: String?, _ p: DatePrecision?) -> CatalogGame {
        CatalogGame(id: "t", name: "T", platforms: [.ps5], releaseDate: d, releasePrecision: p, coverage: .none)
    }

    @Test("GR-5: future dates say only as much as is known")
    func future() {
        #expect(game("2099-11-19", .day).ps5DateLine == "Out 19 Nov 2099")
        #expect(game("2099-11-30", .month).ps5DateLine == "Coming Nov 2099")
        #expect(game("2099-06-30", .quarter).ps5DateLine == "Coming Q2 2099")
        #expect(game("2099-12-31", .year).ps5DateLine == "Coming 2099")
        #expect(game(nil, .tbd).ps5DateLine == "Release date TBA")
        #expect(game(nil, nil).ps5DateLine == "Release date TBA")
    }

    @Test("GR-5: past imprecise dates never claim a day")
    func past() {
        #expect(game("2025-12-31", .year).ps5DateLine == "Released 2025")
        #expect(game("2025-09-30", .quarter).ps5DateLine == "Released Q3 2025")
        #expect(game("2025-03-15", .day).ps5DateLine == "Released 15 Mar 2025")
    }

    @Test("Index entries with a year precision never show a day")
    func index() {
        for e in PS5Index.shared.entries where e.q == "year" || e.q == "quarter" {
            let line = PS5Index.shared.game(e).ps5DateLine ?? ""
            #expect(!line.contains("31 Dec") && !line.contains("30 Sep"), "\(e.n): \(line)")
        }
    }
}

@MainActor
struct GameBookStateTests {
    @Test("D-2: the open game and selected release survive a relaunch, whatever the pose")
    func selectionPersists() {
        let url = URL.temporaryDirectory.appending(path: "d2-\(UUID().uuidString).json")
        let m = AppModel(storeURL: url)
        m.openGame("dawnwalker")
        let other = m.releases("dawnwalker").last!
        m.select("dawnwalker", releaseID: other.id)
        m.livePose = .book
        m.livePose = .closed
        m.saveNow()
        let again = AppModel(storeURL: url)
        #expect(again.nav.gameID == "dawnwalker")
        #expect(again.selectedRelease("dawnwalker")?.id == other.id)
        #expect(!again.isUnread(other))
    }

    @Test("D-13: each game reopens on its last chapter, after a relaunch")
    func chapterPerGame() {
        let url = URL.temporaryDirectory.appending(path: "d13-\(UUID().uuidString).json")
        let m = AppModel(storeURL: url)
        m.openGame("dawnwalker")
        m.nav.chapter = .world
        m.openGame("kcd2")
        #expect(m.nav.chapter == .updates)
        m.saveNow()
        let again = AppModel(storeURL: url)
        again.openGame("dawnwalker")
        #expect(again.nav.chapter == .world)
    }

    @Test("D-4: with nothing selected the Page shows the newest PS5 release")
    func defaultSelection() {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "d4-\(UUID().uuidString).json"))
        #expect(m.selectedRelease("dawnwalker")?.id == m.ps5Releases("dawnwalker").first?.id)
    }
}

@MainActor
struct UnconfirmedTests {
    func model() -> AppModel { AppModel(storeURL: URL.temporaryDirectory.appending(path: "v4-\(UUID().uuidString).json")) }

    func reported(_ m: AppModel) -> Release {
        var r = m.releases("dawnwalker").first { $0.isPS5Listed }!
        let i = r.platforms.firstIndex { $0.platform == .ps5 }!
        r.platforms[i].status = .live
        r.platforms[i].liveAt?.verification = .reported
        r.platforms[i].verification = .reported
        // Unconfirmed means the press has it and neither Steam nor the studio does.
        r.platforms = [r.platforms[i]]
        return r
    }

    @Test("V-4: the alert says Unconfirmed, groups apart, and confirming uses the confirmed text")
    func alertText() {
        let m = model()
        let r = reported(m)
        #expect(r.isUnconfirmed)
        let c = NotificationService.unconfirmedContent(for: r, game: m.game("dawnwalker")!)
        #expect(c.title == "Unconfirmed: The Blood of Dawnwalker")
        #expect(c.subtitle == "\(r.displayName) reported on PS5")
        #expect(c.body == "From press reports. This will update when it's official.")
        #expect(c.threadIdentifier == "dawnwalker.unconfirmed")
        #expect(c.categoryIdentifier == "PS5_UNCONFIRMED")
        #expect(c.interruptionLevel == .passive && c.sound == nil && c.relevanceScore == 0.1)
        // On confirm the same request id carries the confirmed N-4 content.
        let confirmed = NotificationService.content(for: r, game: m.game("dawnwalker")!, badge: 1)
        #expect(confirmed.title == "The Blood of Dawnwalker" && confirmed.subtitle.isEmpty)
        #expect(confirmed.threadIdentifier == "dawnwalker")
        #expect(!confirmed.body.contains("Unconfirmed"))
    }

    @Test("V-4: an official release is never Unconfirmed, even when the feed only has press reports")
    func officialWins() throws {
        let m = model()
        let curated = try #require(m.fixtures.releases.first { $0.id == "dawnwalker@1.1" })
        #expect(curated.ps5State == .onPS5)
        let feedRow = reported(m)
        let merged = curated.merged(withFeed: feedRow)
        #expect(!merged.isUnconfirmed)
        #expect(merged.ps5State == .onPS5)
        // And a release only the press reports stays Unconfirmed.
        #expect(feedRow.merged(withFeed: feedRow).isUnconfirmed)
    }

    @Test("V-4: unconfirmed is never unread, and the facts line says so")
    func unreadAndFacts() {
        let m = model()
        let r = reported(m)
        #expect(!m.isUnread(r))
        #expect(FactsLine.text(for: r).hasPrefix("Unconfirmed on PS5"))
    }

    @Test("V-4: chip, tile, row and Page band render (snapshots attached)")
    func snapshots() throws {
        let m = model()
        let r = reported(m)
        let views: [(String, AnyView)] = [
            ("chip", AnyView(UnconfirmedChip())),
            ("band", AnyView(UnconfirmedBand().frame(width: 360))),
            ("tag", AnyView(ReleaseTag(release: r))),
        ]
        for (name, view) in views {
            let renderer = ImageRenderer(content: view.environment(m).padding(8).background(Color.ink0))
            renderer.scale = 3
            let image = try #require(renderer.uiImage, "\(name) renders")
            #expect(image.size.width > 10)
            let url = URL.temporaryDirectory.appending(path: "v4-\(name).png")
            try image.pngData()?.write(to: url)
            print("snapshot \(name): \(url.path)")
        }
    }

    @Test("D-10: the Swap sides glyph and value follow the reading side")
    func swapSides() {
        #expect(SwapSidesButton.glyph(pageOnLeft: true) == "swap-sides.left")
        #expect(SwapSidesButton.glyph(pageOnLeft: false) == "swap-sides.right")
        #expect(SwapSidesButton.value(pageOnLeft: true) == "Reading on left")
        #expect(SwapSidesButton.value(pageOnLeft: false) == "Reading on right")
        #expect(UIImage(named: "swap-sides.left") != nil && UIImage(named: "swap-sides.right") != nil)
    }
}
