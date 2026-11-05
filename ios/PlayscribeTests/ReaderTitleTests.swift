import Foundation
import Testing
@testable import Playscribe

/// 0.2.0 (Iris): a key change without a heading gets a derived title, never "Change N".
struct ReaderTitleTests {
    @Test("The first sentence is the title, without its full stop")
    func firstSentence() {
        #expect(ReaderTitle.parse("Fixed the quest blocker. Also tuned loot drops.").title == "Fixed the quest blocker")
        #expect(ReaderTitle.parse("Is it fixed? Yes.").title == "Is it fixed")
    }

    @Test("Seven words at most, cut at a word boundary, with an ellipsis only when cut")
    func wordCap() {
        #expect(ReaderTitle.parse("Reworked how companions follow you through narrow doorways and stairs").title
                == "Reworked how companions follow you through narrow…")
        #expect(ReaderTitle.parse("Stability improvements for the map screen now").title == "Stability improvements for the map screen now")
        #expect(ReaderTitle.parse("Short change").title == "Short change")
    }

    @Test("Leading bullets and numbers are stripped")
    func bulletsAndNumbers() {
        #expect(ReaderTitle.parse("• Boss fight tweaks").title == "Boss fight tweaks")
        #expect(ReaderTitle.parse("- Boss fight tweaks").title == "Boss fight tweaks")
        #expect(ReaderTitle.parse("3. Boss fight tweaks").title == "Boss fight tweaks")
        #expect(ReaderTitle.parse("12) Boss fight tweaks").title == "Boss fight tweaks")
    }

    @Test("A Fixed: or Added: prefix becomes the group and leaves the title")
    func groupPrefix() {
        let f = ReaderTitle.parse("Fixed: crash when opening the map")
        #expect(f.group == "Fixed")
        #expect(f.title == "Crash when opening the map")
        #expect(f.body == "Crash when opening the map")
        #expect(ReaderTitle.parse("added: a photo mode").group == "Added")
        #expect(ReaderTitle.parse("• Balance: sword damage lowered").group == "Balance")
        #expect(ReaderTitle.parse("Boss fight tweaks").group == nil)
    }

    @Test("An ordinary heading is not a group")
    func notAGroup() {
        #expect(ReaderTitle.parse("Performance: smoother frame rate").group == nil)
    }

    @Test("A version number is not a sentence end")
    func versionNumbers() {
        #expect(ReaderTitle.parse("Update 1.1 adds new gear").title == "Update 1.1 adds new gear")
    }

    @Test("Lowercase starts are capitalised and empty text still has a title")
    func edges() {
        #expect(ReaderTitle.parse("fixed a crash").title == "Fixed a crash")
        #expect(ReaderTitle.parse("   ").title == "What changed")
        #expect(ReaderTitle.parse("Fixed:").title == "What changed")
    }

    @Test("No title is ever Change N")
    func neverChangeN() {
        for text in ["Boss fight tweaks", "Added a new ending with several branching outcomes", "x", "", "1."] {
            #expect(!ReaderTitle.parse(text).title.hasPrefix("Change "))
        }
    }
}
