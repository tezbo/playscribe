import Foundation
import Testing
@testable import Playscribe

/// r060-dayone-patch-alert-app: the day-one rule (Iris's spec). Shows only for kind dayOne with the PS5 row itself live and
/// official, clears on read, never from a PC row.
@MainActor
struct DayOneAlertTests {
    private func model() -> AppModel {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "dayone-\(UUID().uuidString).json"))
        m.resetDemo()
        return m
    }

    private func release(_ id: String, gameID: String, kind: ReleaseKind, platforms: [PlatformRelease]) -> Release {
        Release(id: id, gameID: gameID, displayName: "Day one patch", kind: kind, kindBasis: .studio, announcedAt: .now,
                notes: [], sourceIDs: [], platforms: platforms)
    }

    private func row(_ p: Platform, _ status: PlatformStatus, _ v: Verification) -> PlatformRelease {
        let now = Date.now
        return PlatformRelease(platform: p, status: status, liveAt: Field(value: now, verification: v, sourceID: "test", checkedAt: now), verification: v)
    }

    private func add(_ m: AppModel, _ r: Release) {
        m.data.simulated.removeAll { $0.id == r.id }
        m.data.simulated.insert(r, at: 0)
    }

    @Test func aDayOnePatchLiveAndOfficialOnPS5SaysSoUntilRead() throws {
        let m = model()
        let gameID = try #require(m.data.collection.first?.gameID)
        let r = release("d1", gameID: gameID, kind: .dayOne, platforms: [row(.ps5, .live, .official)])
        add(m, r)
        #expect(m.isDayOneAlert(r))
        #expect(m.freshLabel(r) == "Day-one patch")
        #expect(m.dayOneNote(r) == "Install this before you first play.")
        #expect(m.latestDeck.first { $0.release?.id == r.id }?.freshLabel == "Day-one patch")
        m.markRead(r.id)
        #expect(!m.isDayOneAlert(r))
        #expect(m.freshLabel(r) == nil)
        #expect(m.dayOneNote(r) == nil)
    }

    /// The Mac's QA route: a day-one card beside a normal "New update" card, and reading clears the day-one one (Iris's
    /// second-visit still).
    @Test func theQARouteShowsADayOneCardBesideANormalOneAndReadingClearsIt() throws {
        let m = model()
        let gameID = try #require(m.data.collection.first?.gameID)
        m.applyQALaunch(route: "dayone/\(gameID)", overlay: false)
        // The feed refresh after launch marks the fixtures' old updates read (markPastAsRead); the route must not care (Mac, dab2f51).
        for r in m.data.collection.flatMap({ m.releases($0.gameID) }) { m.data.read[r.id] = .now }
        let labels = m.latestDeck.compactMap(\.freshLabel)
        #expect(labels.sorted() == ["Day-one patch", "New update"], "deck labels \(labels)")
        let r = try #require(m.latestDeck.first { $0.freshLabel == "Day-one patch" }?.release)
        #expect(m.dayOneNote(r) == "Install this before you first play.")
        m.markRead(r.id)
        #expect(m.dayOneNote(r) == nil)
        #expect(m.latestDeck.first { $0.release?.id == r.id }?.freshLabel != "Day-one patch")
    }

    @Test func anyOtherKindKeepsNewUpdate() throws {
        let m = model()
        let gameID = try #require(m.data.collection.first?.gameID)
        let r = release("p1", gameID: gameID, kind: .patch, platforms: [row(.ps5, .live, .official)])
        add(m, r)
        #expect(!m.isDayOneAlert(r))
        #expect(m.freshLabel(r) == "New update")
        #expect(m.dayOneNote(r) == nil)
    }

    @Test func neverFromAPCRowOrAnUnofficialPS5Row() throws {
        let m = model()
        let gameID = try #require(m.data.collection.first?.gameID)
        // PC live, PS5 row only announced and assumed: the app counts it On PS5 (Steam rule), but the day-one line does not.
        let viaPC = release("d2", gameID: gameID, kind: .dayOne, platforms: [row(.pc, .live, .official), row(.ps5, .announced, .assumed)])
        // PS5 live but only assumed from Steam: not official.
        let assumed = release("d3", gameID: gameID, kind: .dayOne, platforms: [row(.pc, .live, .official), row(.ps5, .live, .assumed)])
        // No PS5 row at all.
        let pcOnly = release("d4", gameID: gameID, kind: .dayOne, platforms: [row(.pc, .live, .official)])
        for r in [viaPC, assumed, pcOnly] {
            add(m, r)
            #expect(!m.isDayOneAlert(r), "\(r.id)")
            #expect(m.dayOneNote(r) == nil, "\(r.id)")
            #expect(m.freshLabel(r) != "Day-one patch", "\(r.id)")
        }
    }
}
