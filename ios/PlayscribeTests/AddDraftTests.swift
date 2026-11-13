import Foundation
import Testing
@testable import Playscribe

/// A-1 to A-9, v0.5.3: the Add UI changes form (sheet, right-page panel, Tabletop panel) while open; the draft survives that and
/// is dropped when Add opens or closes.
@MainActor
struct AddDraftTests {
    private func model() -> AppModel {
        AppModel(storeURL: URL.temporaryDirectory.appending(path: "adddraft-\(UUID().uuidString).json"))
    }

    private func draft(_ q: String) -> AddDraft {
        AddDraft(status: .owned, query: q, picked: [:], pickOrder: [], method: nil, matches: nil,
                 custom: false, customName: "", customPlatform: .ps5, letter: nil)
    }

    @Test func testDraftIsDroppedWhenAddCloses() {
        let m = model()
        m.addSheetOpen = true
        m.addDraft = draft("elden")
        m.addSheetOpen = false
        #expect(m.addDraft == nil)
    }

    @Test func testDraftIsDroppedWhenAddOpens() {
        let m = model()
        m.addDraft = draft("stale")
        m.addSheetOpen = true
        #expect(m.addDraft == nil)
    }

    @Test func testDraftSurvivesWhileAddStaysOpen() {
        let m = model()
        m.addSheetOpen = true
        m.addDraft = draft("elden")
        m.addSheetOpen = true   // a form switch re-renders; the flag does not change
        #expect(m.addDraft?.query == "elden")
    }

    /// A-10, v0.5.3 (Mac, 2be7e23 fold log): a fold builds several sheets in a row, so every one must find the draft and the
    /// keyboard flag; nothing but Add opening or closing may drop them.
    @Test func testDraftAndKeyboardFlagSurviveRepeatedReads() {
        let m = model()
        m.addSheetOpen = true
        m.addDraft = draft("elden")
        m.addKeyboardWanted = true
        for _ in 0..<3 {   // three rebuilt sheets reading the model in turn
            #expect(m.addDraft?.query == "elden")
            #expect(m.addKeyboardWanted)
        }
    }

    @Test func testKeyboardFlagIsDroppedWhenAddClosesOrOpens() {
        let m = model()
        m.addSheetOpen = true
        m.addKeyboardWanted = true
        m.addSheetOpen = false
        #expect(!m.addKeyboardWanted)
        m.addKeyboardWanted = true   // stale from an earlier session
        m.addSheetOpen = true
        #expect(!m.addKeyboardWanted)
    }
}
