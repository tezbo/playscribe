import Foundation
import Testing
@testable import Playscribe

/// The 0.5.0 feed contract (handoff/0.5.0-feed-contract.md, docs/api.md) against what the app
/// decodes. Samples are the contract's own examples plus the extra fields the feed adds; the feed's
/// dates carry fractional seconds. Every field is additive: a missing key is absent, never an error.
@MainActor
struct FeedContractTests {
    let decoder = JSONCoding.decoder

    @Test("alert.from is decoded and drives the 72 hour guard")
    func alertFrom() throws {
        let json = #"{ "style": "standard", "from": "2026-11-03T20:00:00.000Z" }"#
        let alert = try decoder.decode(PlatformRelease.Alert.self, from: Data(json.utf8))
        #expect(alert.style == "standard")
        #expect(alert.from == ISO8601DateFormatter().date(from: "2026-11-03T20:00:00Z"))
        let old = try decoder.decode(PlatformRelease.Alert.self, from: Data(#"{ "style": "standard" }"#.utf8))
        #expect(old.from == nil)
    }

    @Test("Note lines carry pcOnly and category; missing keys mean absent")
    func noteLines() throws {
        let json = #"{ "text": "Steam Deck: fixed stutter", "platforms": ["pc"], "ps5ProOnly": false, "pcOnly": true, "category": "fixed" }"#
        let item = try decoder.decode(NoteItem.self, from: Data(json.utf8))
        #expect(item.pcOnly && item.category == "fixed" && item.isPCOnly)
        let bare = try decoder.decode(NoteItem.self, from: Data(#"{ "text": "Fixed a door" }"#.utf8))
        #expect(!bare.pcOnly && bare.category == nil)
    }

    @Test("Known issues decode with a stable id and an addressedAt with fractional seconds")
    func issues() throws {
        let json = #"[{ "id": "3f9a1c0b7d2e", "text": "Saves may fail to load after fast travel", "status": "addressed", "firstReleaseId": "g@1.0", "addressedBy": "g@1.1", "addressedAt": "2026-10-10T00:00:00.000Z" }, { "id": "a1", "text": "Open one", "status": "open" }]"#
        let list = try decoder.decode([KnownIssue].self, from: Data(json.utf8))
        #expect(list.count == 2 && list[0].isAddressed && list[0].addressedAt != nil)
        #expect(!list[1].isAddressed && list[1].addressedBy == nil)
    }

    @Test("News is { items: [...] } with headline, date and url; a bad item is skipped, not fatal")
    func news() throws {
        let item = #"{ "title": "Dawnwalker roadmap", "date": "2026-11-01T10:00:00.000Z", "url": "https://store.steampowered.com/news/app/3751260/view/1" }"#
        let one = try decoder.decode(NewsItem.self, from: Data(item.utf8))
        #expect(one.title == "Dawnwalker roadmap" && one.date != nil)
        let undated = try decoder.decode(NewsItem.self, from: Data(#"{ "title": "No date", "url": "https://example.com/a" }"#.utf8))
        #expect(undated.date == nil)
    }

    @Test("Similar games decode with an optional cover id")
    func similar() throws {
        let json = #"[{ "igdbId": 1020, "name": "Grand Theft Auto V", "coverId": "co2lbd" }, { "igdbId": 7, "name": "No cover" }]"#
        let list = try decoder.decode([GameBasics.Similar].self, from: Data(json.utf8))
        #expect(list.count == 2 && list[0].coverId == "co2lbd" && list[1].coverId == nil)
    }

    @Test("Digest is optional and tolerates missing counts")
    func digest() throws {
        let full = try decoder.decode(Release.Digest.self, from: Data(#"{ "new": 3, "fixed": 5, "balance": 1, "other": 0, "ps5": 9, "topNew": ["A", "B"] }"#.utf8))
        #expect(full.new == 3 && full.fixed == 5 && full.topNew == ["A", "B"])
        let partial = try decoder.decode(Release.Digest.self, from: Data(#"{ "new": 2 }"#.utf8))
        #expect(partial.new == 2 && partial.fixed == 0 && partial.topNew == nil)
    }

    @Test("Upcoming shards decode every precision, ignore richer fields, and keep tbd undated")
    func upcoming() throws {
        let json = """
        { "games": {
          "12345": { "igdbId": 12345, "name": "Example Game", "date": "2027-03-05", "datePrecision": "day", "status": "dated", "coverId": "co1abc",
                     "summary": "A short summary", "genres": ["RPG"], "trailerId": "abc", "hypes": 12,
                     "move": { "kind": "delayed", "previousDate": "2027-01-01", "previousPrecision": "day", "movedAt": "2026-11-01T00:00:00.000Z" } },
          "2": { "igdbId": 2, "name": "Vague", "date": "2027-12-31", "datePrecision": "year", "status": "announced" },
          "3": { "igdbId": 3, "name": "Undated", "datePrecision": "tbd", "status": "announced" }
        } }
        """
        let shard = try JSONDecoder().decode(UpcomingStore.Shard.self, from: Data(json.utf8))
        #expect(shard.games.count == 3)
        #expect(shard.games["2"]?.datePrecision == "year")
        #expect(shard.games["3"]?.date == nil)
    }
}

@MainActor
struct UpcomingMoveTests {
    @Test("Upcoming moves read as plain lines (0.5.0)")
    func moveLines() {
        typealias M = UpcomingStore.Move
        #expect(M(kind: "dated").line == "Now dated")
        #expect(M(kind: "earlier").line == "Moved earlier")
        #expect(M(kind: "delayed").line == "Delayed")
        #expect(M(kind: "delayed", previousDate: "2027-03-31", previousPrecision: "month").line == "Delayed from March 2027")
        #expect(M(kind: "delayed", previousDate: "2026-12-31", previousPrecision: "quarter").line == "Delayed from Q4 2026")
        #expect(M(kind: "other").line == nil)
    }
}

@MainActor
struct DateMoveAlertTests {
    @Test("A date move alerts only within 72 hours and only for a real kind")
    func freshness() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func move(_ kind: String, hoursAgo: Double) -> UpcomingStore.Move {
            let at = Date(timeIntervalSince1970: now.timeIntervalSince1970 - hoursAgo * 3600)
            return UpcomingStore.Move(kind: kind, movedAt: at.formatted(.iso8601))
        }
        #expect(move("delayed", hoursAgo: 5).isFresh(now: now))
        #expect(move("dated", hoursAgo: 71).isFresh(now: now))
        #expect(!move("delayed", hoursAgo: 80).isFresh(now: now))
        #expect(!move("other", hoursAgo: 1).isFresh(now: now))
        #expect(!UpcomingStore.Move(kind: "delayed").isFresh(now: now))
    }
}
