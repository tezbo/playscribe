import Foundation
import Testing
@testable import Playscribe

/// Build your library in seconds (0.5.0 add flow): how spoken, typed or scanned text is split into titles
/// before it is matched to the catalogue. Nothing is added without the "Add N games" tap.
@MainActor
struct AddMatcherTitleTests {
    @Test func splitsOnAndCommasSemicolonsAndNewLines() {
        #expect(AddMatcher.titles(from: "Elden Ring and Astro Bot, Returnal") == ["Elden Ring", "Astro Bot", "Returnal"])
        #expect(AddMatcher.titles(from: "Elden Ring; Astro Bot\nReturnal") == ["Elden Ring", "Astro Bot", "Returnal"])
    }

    @Test func andIsCaseInsensitive() {
        #expect(AddMatcher.titles(from: "Elden Ring AND Astro Bot") == ["Elden Ring", "Astro Bot"])
    }

    @Test func aWordContainingAndIsNotSplit() {
        // Only a standalone " and " separates titles.
        #expect(AddMatcher.titles(from: "Sandland, Android") == ["Sandland", "Android"])
    }

    @Test func repeatedTitlesAreKeptOnceWhateverTheCase() {
        #expect(AddMatcher.titles(from: "Returnal, returnal and RETURNAL") == ["Returnal"])
    }

    @Test func fragmentsUnderTwoCharactersAreDropped() {
        #expect(AddMatcher.titles(from: "a, Returnal, ,") == ["Returnal"])
    }

    @Test func emptyAndBlankTextGiveNoTitles() {
        #expect(AddMatcher.titles(from: "").isEmpty)
        #expect(AddMatcher.titles(from: " \n ; , ").isEmpty)
    }

    @Test func aTrailingAndLeavesTheLastTitle() {
        #expect(AddMatcher.titles(from: "Returnal and ") == ["Returnal"])
    }
}
