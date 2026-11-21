import Foundation
import Testing
@testable import Playscribe

/// s-06 (0.5.6): a game's update list rows lead with the patch name; the headline is second; a row is never blank; the PS5
/// line comes from the PS5 row's state only (spec acceptance 3); nothing is joined with a dot.
struct UpdateRowTextTests {
    private func release(name: String, headline: String?, ps5: PlatformStatus? = .live, verification: Verification = .official,
                         version: String? = nil, ps4: Bool? = nil) -> Release {
        let day = Date(timeIntervalSince1970: 1_789_516_800)   // 16 Sep 2026, UTC
        var platforms: [PlatformRelease] = []
        if let ps5 {
            platforms.append(PlatformRelease(platform: .ps5, status: ps5,
                                             version: version.map { Field(value: $0, verification: .official, sourceID: "s", checkedAt: day) },
                                             liveAt: ps5 == .live ? Field(value: day, verification: verification, sourceID: "s", checkedAt: day) : nil,
                                             verification: verification))
        }
        var r = Release(id: "g@\(name)", gameID: "g", displayName: name, kind: .patch, kindBasis: .inferred, announcedAt: day,
                        notes: [], sourceIDs: [], platforms: platforms, headline: headline)
        r.ps4 = ps4
        return r
    }

    @Test("Patch name first, headline second")
    func patchFirst() {
        let t = UpdateRowText(release(name: "Patch 1.7.3", headline: "Fixes and tuning"))
        #expect(t.title == "Patch 1.7.3")
        #expect(t.headline == "Fixes and tuning")
        #expect(t.status == "Out on PS5")
    }

    @Test("No patch name: the headline leads alone, never a blank row")
    func noPatchName() {
        let t = UpdateRowText(release(name: "  ", headline: "Seasonal rooms"))
        #expect(t.title == "Seasonal rooms")
        #expect(t.headline == nil)
        let neither = UpdateRowText(release(name: "", headline: nil))
        #expect(!neither.title.isEmpty)
    }

    @Test("A headline that repeats the patch name is not shown twice")
    func noRepeat() {
        let t = UpdateRowText(release(name: "Hotfix 1.7.1", headline: "hotfix 1.7.1"))
        #expect(t.headline == nil)
    }

    @Test("The PS5 line follows the PS5 row's state only, and never shows a version number")
    func ps5Line() {
        #expect(UpdateRowText(release(name: "P", headline: nil, version: "01.004.000")).status == "Out on PS5")
        #expect(UpdateRowText(release(name: "P", headline: nil, ps5: .announced)).status == "Announced for PS5")
        #expect(UpdateRowText(release(name: "P", headline: nil, ps5: .notPlanned)).status == "Not planned for PS5")
        #expect(UpdateRowText(release(name: "P", headline: nil, verification: .reported)).status == "Reported on PS5")
        #expect(UpdateRowText(release(name: "P", headline: nil, ps5: nil)).status == nil)
        let t = UpdateRowText(release(name: "Patch 1.7.3", headline: "Fixes", version: "01.004.000"))
        #expect(![t.title, t.headline ?? "", t.date, t.status ?? ""].contains { $0.contains("01.004.000") })
    }

    @Test("No dot separators in what the row shows or what VoiceOver reads")
    func noDots() {
        let r = release(name: "Patch 1.7.3", headline: "Fixes and tuning", ps4: true)
        let t = UpdateRowText(r)
        let spoken = UpdateRowLabel.spoken(t, unread: true, release: r)
        #expect(spoken == "Patch 1.7.3, New, Fixes and tuning, \(t.date), Out on PS5, PS4 update")
        for s in [t.title, t.headline ?? "", t.date, t.status ?? "", spoken] { #expect(!s.contains("·")) } // dot-ok
    }
}
