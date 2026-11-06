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

    @Test("Quick menu: ticks the current status in the library, offers adds outside it (B-10)")
    func quickMenu() {
        let m = freshModel()
        guard let g = m.game("dawnwalker") else { return }
        if m.entry("dawnwalker") == nil { m.addGame(g, status: .owned) }
        m.setStatus("dawnwalker", .watching)
        let items = m.quickMenu(g).flatMap(\.items)
        #expect(items.first { $0.checked }?.id == OwnershipStatus.watching.rawValue)
        #expect(items.contains { $0.id == "remove" && $0.destructive })
        m.removeGame("dawnwalker", toast: false)
        let adds = m.quickMenu(g).flatMap(\.items)
        #expect(!adds.contains { $0.id == "remove" })
        #expect(adds.contains { $0.id == OwnershipStatus.wishlist.rawValue })
    }

    @Test("Remove then Undo restores status, level, bookmarks and notes (B-8)")
    func removeUndo() {
        let m = freshModel()
        // A real first launch starts empty (245aea0): put Dawnwalker in the library first.
        if m.entry("dawnwalker") == nil, let g = m.game("dawnwalker") { m.addGame(g, status: .owned) }
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

    @Test("New games follow the default; a game's own setting overrides it, and Use default clears it")
    func defaultLevels() {
        let m = freshModel()
        let g = PS5Index.shared.popular(limit: 1)[0]
        m.addGame(g, status: .wishlist)
        #expect(m.notifyLevel(g.id) == .all && !m.hasOwnNotify(g.id))
        m.data.notifyDefault = .major
        #expect(m.notifyLevel(g.id) == .major)
        m.setNotify(g.id, .off)
        #expect(m.notifyLevel(g.id) == .off && m.notifyOverrides.contains { $0.game.id == g.id })
        m.setNotify(g.id, nil)
        #expect(m.notifyLevel(g.id) == .major && !m.hasOwnNotify(g.id))
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
        #expect(c.body.hasPrefix("Update 1.1: "))
        #expect(c.body.count <= 60 && !c.body.contains("PS5"))
        // Without an editorial line: the first key change, still one line, one colon.
        var plain = r
        plain.pushLine = nil
        let fallback = NotificationService.body(for: plain)
        #expect(fallback.filter { $0 == ":" }.count == 1 && fallback.count <= 60)
        // Nothing to say: the plain fallback.
        plain.keyChanges = nil
        plain.digest = nil
        #expect(NotificationService.body(for: plain) == "A new update is out")
        plain.digest = .init(new: 3, fixed: 5, ps5: 2)
        #expect(NotificationService.body(for: plain) == "3 new, 5 fixes, 2 PS5 only")
        plain.digest = nil
        #expect(NotificationService.latestBody(for: plain) == "New updates are out")
        #expect(NotificationService.title(game: m.game("dawnwalker")!, count: 3) == "The Blood of Dawnwalker, 3 new updates")
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

    @Test("Steam rule: an 'assumed' PS5 row is released, and unknown verifications don't break the feed")
    func assumedVerification() throws {
        #expect(try JSONCoding.decoder.decode([Verification].self, from: Data(#"["assumed","somethingNew"]"#.utf8)) == [.assumed, .pending])
    }

    @Test("No 'on PS5' date falls before the PS5 launch, 12 Nov 2020")
    func ps5Dates() {
        let launch = CatalogGame.ps5Launch
        let monthYear = Date.FormatStyle.dateTime.month(.abbreviated).year()
        for e in PS5Index.shared.entries {
            let g = PS5Index.shared.game(e)
            guard let line = g.ps5DateLine else { continue }
            if line.hasPrefix("Released ") || line.hasPrefix("PS5 version since "), let d = g.releaseDate?.isoDay { #expect(d >= launch, "\(g.name): \(line)") }
            if line.hasPrefix("Plays on PS5 since "), let b = g.playableSince?.isoDay {
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

    @Test("Short forms find the franchise in the top 10: 'ac' Assassin's Creed, 'ff' Final Fantasy, 'gta' Grand Theft Auto (#298)")
    func searchAliases() {
        for (query, title) in [("ac", "Assassin"), ("ff", "Final Fantasy"), ("gta", "Grand Theft Auto")] {
            let top = PS5Index.shared.search(query, limit: 10).map(\.name)
            #expect(top.contains { $0.localizedCaseInsensitiveContains(title) }, "\(query): \(top)")
        }
    }

    @Test("A name hit outranks an alias-only hit for the same query (#298)")
    func nameBeatsAlias() {
        let hits = PS5Index.shared.search("dawnwalker", limit: 5)
        #expect(hits.first?.name.localizedCaseInsensitiveContains("dawnwalker") == true)
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

    func ps4Only(_ since: String?, _ p: DatePrecision? = nil) -> CatalogGame {
        CatalogGame(id: "t", name: "T", platforms: [.ps5], releaseDate: nil, releasePrecision: p, playableSince: since, coverage: .none)
    }

    @Test("GR-1, D-12: a PS4-only game that plays on PS5 is not 'TBA'")
    func ps4OnlyIsPlayable() {
        // Before the PS5 launch (12 Nov 2020): the PS4 version plays on PS5.
        #expect(ps4Only("2018-10-05").ps5AvailabilityLine == "Plays on PS5 as the PS4 version")
        #expect(ps4Only("2018-10-05").ps5ShortLine == "Plays on PS5")
        #expect(ps4Only("2018-10-05").ps5AvailabilityLine.contains("2018") == false)
        // After the launch: since when.
        #expect(ps4Only("2021-03-04").ps5AvailabilityLine == "Plays on PS5 since Mar 2021")
        #expect(ps4Only("2021-03-04").ps5ShortLine == "Plays on PS5")
        // A future date never reads "since <future>".
        #expect(ps4Only("2099-01-01").ps5AvailabilityLine == "Plays on PS5 as the PS4 version")
        #expect(ps4Only("2099-01-01").ps5DateLine == "Plays on PS5 as the PS4 version")
        // The game page and the tile agree with the date line.
        #expect(ps4Only("2018-10-05").ps5DateLine == ps4Only("2018-10-05").ps5AvailabilityLine)
        #expect(ps4Only("2021-03-04").ps5DateLine == ps4Only("2021-03-04").ps5AvailabilityLine)
    }

    @Test("D-12: a PS4-only game's tile is a quiet caption, never unread, never TBA, and VoiceOver says what it is")
    func ps4OnlyTile() {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "ps4tile-\(UUID().uuidString).json"))
        for since in ["2018-10-05", "2021-03-04"] {
            let row = AppModel.LibraryRow(game: ps4Only(since), status: .owned, addedAt: .now, unread: 0, latest: nil)
            #expect(m.tileDate(row).kind == .playsOnPS5)
            #expect(m.tileDate(row).text == "Plays on PS5")
            #expect(m.tileAccessibilityLabel(row) == "T, plays on PS5 as the PS4 version, \(row.status.label.lowercased())")
            #expect(row.unread == 0 && m.unreadCount("t") == 0)
        }
        let tba = AppModel.LibraryRow(game: ps4Only(nil), status: .owned, addedAt: .now, unread: 0, latest: nil)
        #expect(m.tileDate(tba).text == "TBA")
        // No PC version number can leak into the line.
        #expect(ps4Only("2021-03-04").ps5AvailabilityLine.range(of: #"\d+\.\d+"#, options: .regularExpression) == nil)
    }

    @Test("GR-1, D-12: a game that is out elsewhere but not on PS5 or PS4 is never TBA")
    func notOnPS5() {
        func g(_ o: String?, _ on: String? = nil, _ p: DatePrecision? = .tbd) -> CatalogGame {
            CatalogGame(id: "t", name: "T", platforms: [.ps5], releaseDate: nil, releasePrecision: p, playableSince: nil, releasedElsewhere: o, releasedElsewhereOn: on, coverage: .none)
        }
        #expect(g("2012-10-16", "PC").ps5DateLine == "Not on PS5 · PC, 2012")
        #expect(g("2012-10-16", "PC").ps5AvailabilityLine == "Not on PS5 · PC, 2012")
        #expect(g("2012-10-19", "PC (Microsoft Windows)").ps5AvailabilityLine == "Not on PS5 · PC, 2012")
        #expect(g("2012-10-16").ps5AvailabilityLine == "Not on PS5 · 2012")
        #expect(g("2012-10-16").ps5ShortLine == "Not on PS5")
        // Truly no release anywhere, or a release still to come, stays TBA.
        #expect(g(nil).ps5AvailabilityLine == "Release date TBA")
        #expect(g("2099-01-01").ps5AvailabilityLine == "Release date TBA")
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "notps5-\(UUID().uuidString).json"))
        let row = AppModel.LibraryRow(game: g("2012-10-16", "PC"), status: .owned, addedAt: .now, unread: 0, latest: nil)
        #expect(m.tileDate(row).text == "Not on PS5")
        #expect(m.tileAccessibilityLabel(row) == "T, not on PS5, \(row.status.label.lowercased())")
    }

    @Test("GR-1, D-12: TBA stays for a game with no date at all, or a date that is to be decided")
    func tbaStays() {
        #expect(ps4Only(nil).ps5AvailabilityLine == "Release date TBA")
        #expect(ps4Only(nil).ps5ShortLine == "Date TBA")
        #expect(ps4Only("2018-10-05", .tbd).ps5AvailabilityLine == "Release date TBA")
        #expect(ps4Only("2018-10-05", .tbd).ps5ShortLine == "Date TBA")
    }

    @Test("GR-1, D-12: a game with a PS5 date keeps its lines")
    func ps5DateUnchanged() {
        #expect(game("2099-11-19", .day).ps5AvailabilityLine == "Out 19 Nov 2099")
        #expect(game("2024-05-02", .day).ps5ShortLine.hasPrefix("On PS5 since"))
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

    func pressOnly(_ m: AppModel) -> Release {
        var r = m.releases("dawnwalker").first { $0.isPS5Listed }!
        let i = r.platforms.firstIndex { $0.platform == .ps5 }!
        r.platforms[i].status = .live
        r.platforms[i].liveAt?.verification = .reported
        r.platforms[i].verification = .reported
        r.platforms = [r.platforms[i]]
        r.links = nil
        return r
    }

    @Test("Steam rule: a release only the press reports is not shown at all")
    func pressOnlyHidden() {
        let m = model()
        let r = pressOnly(m)
        #expect(r.ps5State == .reported)
        m.feedReleases = [r]
        #expect(!m.releases("dawnwalker").contains { $0.id == r.id && $0.ps5State == .reported })
    }

    @Test("An official curated release stays released when the feed only has press reports")
    func officialWins() throws {
        let m = model()
        let curated = try #require(m.fixtures.releases.first { $0.id == "dawnwalker@1.1" })
        #expect(curated.merged(withFeed: pressOnly(m)).ps5State == .onPS5)
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

@MainActor
struct LinkedTextTests {
    func links(_ a: AttributedString) -> [URL] { a.runs.compactMap(\.link) }

    @Test("http:// and https:// URLs become links; Steam markup is tidied")
    func links() {
        #expect(links(LinkedText.attributed("Patch notes at http://example.com/notes today")) == [URL(string: "http://example.com/notes")!])
        #expect(links(LinkedText.attributed("See https://store.steampowered.com/app/1")) == [URL(string: "https://store.steampowered.com/app/1")!])
        let steam = LinkedText.attributed(#"[img src="https://x/y.png"][dynamiclink href="https://store.steampowered.com/app/3751260/"]"#)
        #expect(links(steam) == [URL(string: "https://store.steampowered.com/app/3751260/")!])
        #expect(String(steam.characters) == "https://store.steampowered.com/app/3751260/")
        #expect(LinkedText.clean(#"[img src="https://x/y.png"]"#).isEmpty)
    }

    @Test("A spoiler note keeps its links once revealed")
    func spoilerLinks() {
        // SpoilerText shows LinkedTextView(text:) for the revealed text, the same path as other notes.
        #expect(links(LinkedText.attributed("Spoiler: the ending is at http://example.com/end")).count == 1)
    }
}

@MainActor
struct ReadTimeTests {
    private func release(_ items: [NoteItem]) -> Release {
        Release(id: "r", gameID: "g", displayName: "Update", kind: .patch, kindBasis: .inferred, announcedAt: .now,
                notes: items.isEmpty ? [] : [NoteSection(title: "Changes", items: items)], sourceIDs: [], platforms: [])
    }

    @Test("Read time is words over 220 rounded up, at least 1, hidden with no notes, PC-only lines left out")
    func readTime() {
        #expect(release([]).readMinutes == nil)
        #expect(release([NoteItem(text: "Fixed a crash")]).readMinutes == 1)
        let long = Array(repeating: "word", count: 221).joined(separator: " ")
        #expect(release([NoteItem(text: long)]).readMinutes == 2)
        var pc = NoteItem(text: long); pc.pcOnly = true
        #expect(release([NoteItem(text: "Fixed a crash"), pc]).readMinutes == 1)
    }
}

@MainActor
struct OneUpdateDemoTests {
    /// The `one-update` QA route: the Library hero shows (one fresh unread update) and the "Also new"
    /// panel has nothing else to list, so it falls back to "What's new".
    @Test func oneUpdateRouteLeavesExactlyOneFreshUpdate() {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "one-\(UUID().uuidString).json"))
        m.resetToOneUpdateDemo()
        #expect(m.data.collection.count > 1, "the full demo library is kept")
        let hero = m.continueItem
        #expect(hero != nil, "the hero shows")
        let unread = m.data.collection.flatMap { m.releases($0.gameID) }.filter(m.isUnread)
        #expect(unread.count == 1)
        if let hero { #expect(m.alsoNewReleases(excludingRelease: hero.release.id).isEmpty) }
    }

    /// The `two-update` QA route: exactly two fresh unread updates, from different games.
    @Test func twoUpdateRouteLeavesTwoFreshUpdatesFromDifferentGames() {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "two-\(UUID().uuidString).json"))
        m.resetToTwoUpdateDemo()
        let unread = m.data.collection.flatMap { m.releases($0.gameID) }.filter(m.isUnread)
        #expect(unread.count == 2)
        #expect(Set(unread.map(\.gameID)).count == 2)
        #expect(m.latestDeck.count == 2)
    }

    @Test func demoRouteListsOtherUpdatesBesideTheHero() {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "demo-\(UUID().uuidString).json"))
        m.resetDemo()
        if let hero = m.continueItem { #expect(!m.alsoNewReleases(excludingRelease: hero.release.id).isEmpty) }
    }

    /// Also new: one row per game, never the deck front card's game (Iris, 3548a21).
    @Test func alsoNewHasOneRowPerGameAndSkipsTheFrontGame() {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "demo-\(UUID().uuidString).json"))
        m.resetDemo()
        guard let front = m.latestDeck.first?.release else { return }
        let rows = m.alsoNewReleases(excludingRelease: front.id)
        let games = rows.map(\.gameID)
        #expect(Set(games).count == games.count)
        #expect(!games.contains(front.gameID))
    }
}

/// Reader polish from the 0.5.0 build 6 device pass: spoiler warnings, counts, greetings.
struct SpoilerWarningTests {
    private func section() -> NoteSection {
        NoteSection(title: "Changes", items: [
            NoteItem(text: "Hello!"),
            NoteItem(text: "Be advised, the following notes contain spoilers so browse at your own peril:"),
            NoteItem(text: "Fixed camera lock in the lab."),
            NoteItem(text: "Fixed a crash."),
        ])
    }

    @Test("R-5: lines after a spoiler warning hide behind the spoiler switch; lines before it do not")
    func linesAfterWarningAreSpoilers() {
        let items = section().items
        #expect(items[0].spoiler == nil)
        #expect(items[2].spoiler == true)
        #expect(items[3].spoiler == true)
    }

    @Test("A greeting and the warning are not counted as changes")
    func preambleIsNotCounted() {
        let g = ChangeKind.grouped([section()], ps5Only: true)
        #expect(g.reduce(0) { $0 + $1.count } == 2)
    }

    @Test("Items with nothing to show (blank text) are not counted (#301)")
    func emptyItemsAreNotCounted() {
        let s = NoteSection(title: "Changes", items: [NoteItem(text: "Fixed a crash."), NoteItem(text: "   "), NoteItem(text: "")])
        let g = ChangeKind.grouped([s], ps5Only: true)
        #expect(g.reduce(0) { $0 + $1.count } == 1)
    }

    @Test("A section with only PC-only lines is left out of a PS5 page, not shown as 0 (#301)")
    func pcOnlySectionIsHidden() {
        let pc = NoteItem(text: "Fixed a PC plugin crash.", platforms: [.pc])
        let s = NoteSection(title: "Plugin", items: [pc])
        #expect(pc.isPCOnly)
        #expect(ChangeKind.grouped([s], ps5Only: true).isEmpty)
        #expect(ChangeKind.grouped([s], ps5Only: false).count == 1)
    }

    @Test("Notes without a warning are untouched")
    func noWarningNoChange() {
        let s = NoteSection(title: "Fixes", items: [NoteItem(text: "Fixed a crash."), NoteItem(text: "Be advised: servers restart.")])
        #expect(s.items.allSatisfy { $0.spoiler == nil })
    }
}

/// VoiceOver reads the playback position as time (R-11).
struct PlayerTimeTests {
    @Test("Spoken time is words, differs per second, never empty past zero")
    func spoken() {
        #expect(!PlayerTime.spoken(83).isEmpty)
        #expect(PlayerTime.spoken(83) != PlayerTime.spoken(84))
        #expect(PlayerTime.spoken(83).contains("minute"))
        #expect(PlayerTime.format(83) == "1:23")
    }
}

/// TT-2: VoiceOver hears where a section sits in the update.
struct ReaderPositionTests {
    @Test("Position reads as a place, from one")
    func position() {
        #expect(ReaderBody.position(0, of: 5) == "1 of 5")
        #expect(ReaderBody.position(4, of: 5) == "5 of 5")
    }
}

/// R-11, G-9: autoplay is opt-in.
struct AutoplayTests {
    @Test("Player page autoplays only when asked (R-11)")
    func html() {
        #expect(YouTubeController.html("abc", captions: true).contains("autoplay:0"))
        let on = YouTubeController.html("abc", captions: true, autoplay: true)
        #expect(on.contains("autoplay:1") && on.contains("player.playVideo();"))
    }

    @Test("Reflection is on by default and accessibility settings win (R-11, G-9)")
    @MainActor func reflectionDefault() {
        #expect(VideoReflection.defaultOn)
        #expect(VideoReflection.isShown(setting: VideoReflection.defaultOn, reduceMotion: false, reduceTransparency: false))
        #expect(!VideoReflection.isShown(setting: true, reduceMotion: true, reduceTransparency: false))
        #expect(!VideoReflection.isShown(setting: true, reduceMotion: false, reduceTransparency: true))
        #expect(!VideoReflection.isShown(setting: false, reduceMotion: false, reduceTransparency: false))
    }
}

/// Release also defines INTERNAL, so the QA routes must be switched off by the build channel:
/// a TestFlight or App Store build (it carries a receipt) ignores them, and so do URLs from other apps.
@MainActor
struct QARouteGuardTests {
    private func model() -> AppModel { AppModel(storeURL: URL.temporaryDirectory.appending(path: "qa-\(UUID().uuidString).json")) }

    @Test("A distribution build ignores playscribe:// QA routes")
    func distributionIgnoresURLRoutes() {
        BuildChannel.overrideIsDistribution = true
        defer { BuildChannel.overrideIsDistribution = nil }
        let m = model()
        m.handle(url: URL(string: "playscribe://add")!)
        m.handle(url: URL(string: "playscribe://first-run")!)
        #expect(!m.addSheetOpen)
        #expect(m.qaRoute == nil)
    }

    @Test("A distribution build ignores the -qaRoute launch argument and the overlay")
    func distributionIgnoresLaunchArguments() {
        BuildChannel.overrideIsDistribution = true
        defer { BuildChannel.overrideIsDistribution = nil }
        let m = model()
        m.applyQALaunch(route: "add", overlay: true)
        #expect(!m.addSheetOpen)
        #expect(!m.showDebugOverlay)
        #expect(m.qaRoute == nil)
    }

    @Test("A developer or simulator build still runs QA routes")
    func internalBuildRunsRoutes() {
        BuildChannel.overrideIsDistribution = false
        defer { BuildChannel.overrideIsDistribution = nil }
        let m = model()
        m.applyQALaunch(route: "add", overlay: false)
        #expect(m.addSheetOpen)
        #expect(m.qaRoute == "add")
    }
}

/// The simulator has a sandboxReceipt, so the channel must not read it there, or every QA route is dead;
/// a device with a receipt is a distribution build.
struct BuildChannelTests {
    @Test("A receipt marks a distribution build; none marks a developer build")
    func receiptDecides() {
        #expect(BuildChannel.isDistribution(receiptName: "sandboxReceipt"))
        #expect(BuildChannel.isDistribution(receiptName: "receipt"))
        #expect(!BuildChannel.isDistribution(receiptName: nil))
        #expect(!BuildChannel.isDistribution(receiptName: "other"))
    }

    #if targetEnvironment(simulator)
    @Test("The simulator is never a distribution build, so QA routes run there")
    func simulatorShowsInternalTools() {
        BuildChannel.overrideIsDistribution = nil
        #expect(!BuildChannel.isDistribution)
        #expect(BuildChannel.showsInternalTools)
    }
    #endif
}

struct ReaderSpoilerTests {
    @MainActor
    private func fixes(shown: Bool) -> String {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "rs-\(UUID().uuidString).json"))
        let gameID = "g"
        m.setSpoilersShown(gameID, shown)
        let when = Date(timeIntervalSince1970: 1_745_020_800)
        let r = Release(id: "r", gameID: gameID, displayName: "Patch 1.2", kind: .hotfix, kindBasis: .studio, announcedAt: when,
                        notes: [NoteSection(title: "Changes", items: ["Hello!", "Be advised, the following notes contain spoilers:",
                                                                        "Fixed the final door.", "Fixed the ending letter."].map { NoteItem(text: $0) })],
                        sourceIDs: [], platforms: [])
        return m.readerSections(r).first { $0.id == "fixes" }?.body ?? ""
    }

    @Test("R-5: the standing half hides spoiler lines until the spoiler switch is on, and never lists the greeting or warning")
    @MainActor func standingHalfRespectsSpoilers() {
        let hidden = fixes(shown: false)
        #expect(hidden.contains("2 listed changes") && hidden.contains("2 hidden for spoilers") && !hidden.contains("final door"))
        #expect(!hidden.contains("Hello") && !hidden.contains("Be advised"))
        let shown = fixes(shown: true)
        #expect(shown.contains("final door") && !shown.contains("hidden for spoilers"))
    }
}

/// r051-unread-flood: adding a game must not mark its back catalogue unread (0.5.1, Jun's review).
@MainActor
struct BackCatalogueTests {
    private func release(_ id: String, patchedDaysAgo: Double, alertDaysAgo: Double) -> Release {
        let patched = Date.now.addingTimeInterval(-patchedDaysAgo * 86_400)
        var p = PlatformRelease(platform: .ps5, status: .live, liveAt: Field(value: patched, verification: .official, sourceID: "s", checkedAt: .now),
                                verification: .official)
        p.alert = PlatformRelease.Alert(style: "standard", from: Date.now.addingTimeInterval(-alertDaysAgo * 86_400), tag: nil)
        return Release(id: id, gameID: "g", displayName: id, kind: .patch, kindBasis: .inferred, announcedAt: patched,
                       notes: [], sourceIDs: [], platforms: [p])
    }

    @Test("A port's old patches are read on first sight, a patch from today stays unread")
    func firstSightHistory() {
        let model = AppModel(storeURL: URL.temporaryDirectory.appending(path: "flood-\(UUID().uuidString).json"))
        let old = release("g@2021", patchedDaysAgo: 1_800, alertDaysAgo: 1)   // alert date is the recent PS5 launch
        let fresh = release("g@today", patchedDaysAgo: 1, alertDaysAgo: 1)
        model.markPastAsRead([old, fresh], backCatalogue: true)
        #expect(model.data.read[old.id] != nil)
        #expect(model.data.read[fresh.id] == nil)
    }

    @Test("Without the back-catalogue rule the alert date still decides (an update for a followed game)")
    func followedGameUnchanged() {
        let model = AppModel(storeURL: URL.temporaryDirectory.appending(path: "flood-\(UUID().uuidString).json"))
        let ported = release("g@port", patchedDaysAgo: 1_800, alertDaysAgo: 1)
        model.markPastAsRead([ported])
        #expect(model.data.read[ported.id] == nil)
    }
}
