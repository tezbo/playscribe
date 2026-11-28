import Foundation
import Testing
@testable import Playscribe

/// bug-077: the first-run tour's game row offers only games whose newest PS5 update has notes, in Popular order.
@MainActor
struct TourGamesTests {
    private func release(_ id: String, daysAgo: Double, notes: Bool, ps5: Bool = true) -> Release {
        let at = Date(timeIntervalSince1970: 1_790_000_000 - daysAgo * 86_400)
        let live = Field(value: at, verification: .official, sourceID: "s", checkedAt: at)
        let platforms = [PlatformRelease(platform: ps5 ? .ps5 : .pc, status: .live, version: nil, liveAt: live, verification: .official)]
        return Release(id: id, gameID: "g", displayName: id, kind: .patch, kindBasis: .inferred, announcedAt: at,
                       notes: notes ? [NoteSection(title: "Fixes", items: [NoteItem(text: "Fixed a crash.")])] : [],
                       sourceIDs: [], platforms: platforms, headline: nil)
    }

    @Test("Only the newest PS5 update counts: older notes don't qualify a game whose newest update has none (GTA V)")
    func newestPS5UpdateDecides() {
        #expect(AppModel.newestPS5HasNotes([release("old", daysAgo: 30, notes: true), release("new", daysAgo: 1, notes: false)]) == false)
        #expect(AppModel.newestPS5HasNotes([release("new", daysAgo: 1, notes: true), release("old", daysAgo: 30, notes: false)]) == true)
        // A PC-only update is never the newest PS5 one.
        #expect(AppModel.newestPS5HasNotes([release("pc", daysAgo: 0, notes: false, ps5: false), release("ps5", daysAgo: 5, notes: true)]) == true)
        // No PS5 update at all (Roblox: nothing in the feed): not offered.
        #expect(AppModel.newestPS5HasNotes([]) == false)
        // A section with no items is not a notes body.
        var empty = release("hollow", daysAgo: 1, notes: false)
        empty.notes = [NoteSection(title: "Fixes", items: [])]
        #expect(AppModel.newestPS5HasNotes([empty]) == false)
    }

    @Test("Popular order is kept, games without notes are skipped, and the row stops at its limit")
    func popularOrderSkipAndLimit() {
        let popular = ["roblox", "gta5", "minecraft", "witcher-3", "marvel-rivals", "battlefield-6"].map {
            CatalogGame(id: $0, name: $0, platforms: [.ps5], coverage: .none)
        }
        let withNotes: Set = ["minecraft", "witcher-3", "marvel-rivals", "battlefield-6"]
        let row = AppModel.tourGames(popular, limit: 3) { withNotes.contains($0.id) }
        #expect(row.map(\.id) == ["minecraft", "witcher-3", "marvel-rivals"])
    }

    @Test("Fewer than 3 games with notes (first launch before the feed syncs): the row is plain Popular, never empty (Quinn, #677)")
    func fallsBackToPopularBelowThree() {
        let popular = ["roblox", "gta5", "minecraft", "witcher-3", "marvel-rivals"].map {
            CatalogGame(id: $0, name: $0, platforms: [.ps5], coverage: .none)
        }
        #expect(AppModel.tourGames(popular, limit: 4) { _ in false }.map(\.id) == ["roblox", "gta5", "minecraft", "witcher-3"])
        #expect(AppModel.tourGames(popular, limit: 4) { $0.id == "minecraft" || $0.id == "witcher-3" }.map(\.id)
                == ["roblox", "gta5", "minecraft", "witcher-3"])
        // Three that qualify is enough: the filter holds.
        let three: Set = ["gta5", "witcher-3", "marvel-rivals"]
        #expect(AppModel.tourGames(popular, limit: 4) { three.contains($0.id) }.map(\.id) == ["gta5", "witcher-3", "marvel-rivals"])
    }
}
