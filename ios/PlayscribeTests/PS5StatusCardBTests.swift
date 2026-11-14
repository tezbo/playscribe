import Foundation
import Testing
@testable import Playscribe

/// 0.5.6 Card B (docs/ux-acceptance.md PS5 states, V-3): the PS5 status block comes from the PS5 row's state only; a live update
/// shows "Out on PS5" and, only when the PS5 row has its own number, "This update is <n> on PS5". Never a PC number, never a
/// claim about what is installed. The cover chip reads "Out on PS5" with the PS5 number as a separate chip, no dot.
struct PS5StatusCardBTests {
    private let day = Date(timeIntervalSince1970: 1_789_516_800)

    private func release(name: String = "Patch 1.7.3", ps5: PlatformStatus?, verification: Verification = .official,
                         ps5Version: String? = nil, pcVersion: String? = nil) -> Release {
        var platforms: [PlatformRelease] = []
        let at = day
        func text(_ v: String?) -> Field<String>? { v.map { Field(value: $0, verification: .official, sourceID: "s", checkedAt: at) } }
        let live = Field(value: day, verification: .official, sourceID: "s", checkedAt: day)
        if let pcVersion {
            platforms.append(PlatformRelease(platform: .pc, status: .live, version: text(pcVersion), liveAt: live, verification: .official))
        }
        if let ps5 {
            platforms.append(PlatformRelease(platform: .ps5, status: ps5, version: text(ps5Version),
                                             liveAt: ps5 == .live ? live : nil, verification: verification))
        }
        return Release(id: "g@\(name)", gameID: "g", displayName: name, kind: .patch, kindBasis: .inferred, announcedAt: day,
                       notes: [], sourceIDs: [], platforms: platforms, headline: nil)
    }

    @Test("Live with a PS5 number: two lines, read together")
    func liveWithVersion() {
        let s = PS5StatusLines(release(ps5: .live, ps5Version: "01.004.000"))
        #expect(s.primary == "Out on PS5")
        #expect(s.version == "This update is 01.\u{2060}004.\u{2060}000 on PS5") // a version never breaks at its dots
        #expect(s.version?.replacingOccurrences(of: "\u{2060}", with: "") == "This update is 01.004.000 on PS5")
        #expect(s.spoken == "Out on PS5. This update is 01.004.000 on PS5")
    }

    @Test("Live without a PS5 number: one line, a PC number is never shown")
    func liveWithoutVersion() {
        let s = PS5StatusLines(release(ps5: .live, pcVersion: "1.7.3"))
        #expect(s.primary == "Out on PS5")
        #expect(s.version == nil)
        #expect(s.spoken == "Out on PS5")
    }

    @Test("A blank PS5 number counts as none")
    func blankVersion() {
        #expect(PS5StatusLines(release(ps5: .live, ps5Version: "  ")).version == nil)
    }

    @Test("Announced, not planned and not on PS5 yet keep their words and carry no version")
    func otherStates() {
        #expect(PS5StatusLines(release(ps5: .announced, ps5Version: "01.002.000")).primary == "Announced for PS5")
        #expect(PS5StatusLines(release(ps5: .announced, ps5Version: "01.002.000")).version == nil)
        #expect(PS5StatusLines(release(ps5: .notPlanned)).primary == "Not planned for PS5")
        #expect(PS5StatusLines(release(ps5: nil)).primary == "Not on PS5 yet")
        #expect(PS5StatusLines(release(ps5: nil, pcVersion: "2.0")).version == nil)
    }

    @Test("No wording names a PS5 screen or says what is installed")
    func noInstalledClaims() {
        for r in [release(ps5: .live, ps5Version: "01.004.000"), release(ps5: .announced), release(ps5: nil)] {
            let all = PS5StatusLines(r).spoken.lowercased()
            #expect(!all.contains("installed") && !all.contains("your ps5") && !all.contains("settings") && !all.contains("·")) // dot-ok: asserts the dot is absent
        }
    }

    @Test("Cover chip: Out on PS5, the PS5 number as its own chip, no dot")
    func coverChips() {
        let game = CatalogGame(id: "g", name: "G", platforms: [.ps5], coverage: .none)
        let with = FrontCoverPlate.chips(DeckCard(game: game, release: release(name: "Update 1.1", ps5: .live, ps5Version: "01.004.000"),
                                                  unread: true, date: day))
        #expect(with.first?.text == "Out on PS5")
        #expect(with.contains { $0.text == "01.004.000" })
        let without = FrontCoverPlate.chips(DeckCard(game: game, release: release(name: "Update 1.1", ps5: .live, pcVersion: "1.1"),
                                                     unread: true, date: day))
        #expect(without.first?.text == "Out on PS5")
        #expect(!without.contains { $0.text.contains("1.1") })
        #expect((with + without).allSatisfy { !$0.text.contains("·") }) // dot-ok: asserts the dot is absent
    }

    @Test("A game with no details gets one line, never blank")
    func noDetails() {
        #expect(GameBasicsView.noDetailsLine == "More about this game soon.")
        #expect(GameBasicsView.hasNoDetails(info: nil, summary: nil, trailers: 0))
        #expect(!GameBasicsView.hasNoDetails(info: nil, summary: "About text", trailers: 0))
        #expect(!GameBasicsView.hasNoDetails(info: nil, summary: nil, trailers: 1))
    }
}

/// Iris's final hero heights for the update page (#529), std then AX5. Tabletop has no band (the art is the stage).
struct HeroBandHeightTests {
    @Test func heightsPerPose() {
        #expect(PageArtBand.height(pose: .closed, landscape: false, ax: false) == 130)
        #expect(PageArtBand.height(pose: .closed, landscape: false, ax: true) == 84)
        #expect(PageArtBand.height(pose: .closed, landscape: true, ax: false) == 88)
        #expect(PageArtBand.height(pose: .closed, landscape: true, ax: true) == 52)
        #expect(PageArtBand.height(pose: .flat, landscape: false, ax: false) == 170)
        #expect(PageArtBand.height(pose: .flat, landscape: true, ax: true) == 110)
        #expect(PageArtBand.height(pose: .book, landscape: true, ax: false) == 170)
        #expect(PageArtBand.height(pose: .book, landscape: true, ax: true) == 110)
    }
}
