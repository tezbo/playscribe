import Foundation
import Testing
@testable import Playscribe

/// 0.2.0: a key change without a "Heading: text" split gets a derived title, never "Change N".
struct ReaderTitleTests {
    @Test("Short first sentence is the title, without the full stop")
    func shortSentence() {
        #expect(ReaderTitle.derived(from: "Fixed the quest blocker. Also tuned loot drops.") == "Fixed the quest blocker")
    }

    @Test("Long text is cut at six words with an ellipsis")
    func longText() {
        #expect(ReaderTitle.derived(from: "Reworked how companions follow you through narrow doorways and stairs") == "Reworked how companions follow you…")
    }

    @Test("Exactly six words has no ellipsis")
    func sixWords() {
        #expect(ReaderTitle.derived(from: "Stability improvements for the map screen") == "Stability improvements for the map screen")
    }

    @Test("Lowercase starts are capitalised and empty text still has a title")
    func edges() {
        #expect(ReaderTitle.derived(from: "fixed a crash") == "Fixed a crash")
        #expect(ReaderTitle.derived(from: "   ") == "What changed")
    }

    @Test("A version number is not mistaken for a sentence end")
    func versionNumbers() {
        #expect(ReaderTitle.derived(from: "Update 1.1 adds new gear") == "Update 1.1 adds new gear")
    }

    @Test("No title is ever Change N")
    func neverChangeN() {
        for text in ["Boss fight tweaks", "Added a new ending with several branching outcomes", "x"] {
            #expect(!ReaderTitle.derived(from: text).hasPrefix("Change "))
        }
    }
}
