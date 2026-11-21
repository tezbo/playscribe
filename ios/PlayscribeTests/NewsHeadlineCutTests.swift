import Foundation
import Testing
@testable import Playscribe

/// G-8 (Iris): a Library News headline that does not fit ends on a whole word, never "Award N…".
@MainActor
struct NewsHeadlineCutTests {
    private let title = "Two Golden Joystick Award Nominations for The Blood of Dawnwalker, Including Best Storytelling"

    @Test func everyCutOfALibraryNewsHeadlineEndsOnAWholeWord() {
        let words = WholeWordText.words(of: title)
        for v in WholeWordText.variants(of: title).dropFirst() {
            let kept = String(v.dropLast())
            let lastWord = WholeWordText.words(of: kept).last ?? ""
            #expect(words.contains { $0 == lastWord || $0.trimmingCharacters(in: CharacterSet(charactersIn: ",;:.")) == lastWord }, "\(v): the last kept word is a whole word of the headline")
        }
    }

    @Test func noCutLeavesALoneInitialBeforeTheEllipsis() {
        for v in WholeWordText.variants(of: title).dropFirst() {
            #expect(!v.hasSuffix(" N\u{2026}") && !v.hasSuffix(" N"), "\(v)")
        }
        #expect(WholeWordText.variants(of: title).contains("Two Golden Joystick Award\u{2026}"))
    }
}
