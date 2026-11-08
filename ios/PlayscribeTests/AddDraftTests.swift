import XCTest
@testable import Playscribe

/// A-1 to A-9, v0.5.3: the Add UI changes form (sheet, right-page panel, Tabletop panel) while open; the draft survives that and
/// is dropped when Add opens or closes.
@MainActor
final class AddDraftTests: XCTestCase {
    private func model() -> AppModel {
        AppModel(storeURL: URL.temporaryDirectory.appending(path: "adddraft-\(UUID().uuidString).json"))
    }

    private func draft(_ q: String) -> AddDraft {
        AddDraft(status: .owned, query: q, picked: [:], pickOrder: [], method: nil, matches: nil,
                 custom: false, customName: "", customPlatform: .ps5, letter: nil)
    }

    func testDraftIsDroppedWhenAddCloses() {
        let m = model()
        m.addSheetOpen = true
        m.addDraft = draft("elden")
        m.addSheetOpen = false
        XCTAssertNil(m.addDraft)
    }

    func testDraftIsDroppedWhenAddOpens() {
        let m = model()
        m.addDraft = draft("stale")
        m.addSheetOpen = true
        XCTAssertNil(m.addDraft)
    }

    func testDraftSurvivesWhileAddStaysOpen() {
        let m = model()
        m.addSheetOpen = true
        m.addDraft = draft("elden")
        m.addSheetOpen = true   // a form switch re-renders; the flag does not change
        XCTAssertEqual(m.addDraft?.query, "elden")
    }
}
