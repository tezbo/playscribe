import Foundation
import Testing
@testable import Playscribe

/// r053-hero-duplicate-title-no-notes (G-8): a hero card for a game with no release has the game name as its headline, so
/// the line under it must never repeat the name. Tracked games say there are no patch notes yet; games the feed does not
/// follow say so, in the Page's own words.
@MainActor
struct DeckNoReleaseLineTests {
    @Test func aTrackedGameWithNoReleaseSaysNoPatchNotesYet() {
        #expect(DeckCard.noReleaseLine(tracked: true) == "No patch notes yet")
    }

    @Test func anUntrackedGameSaysWeDoNotTrackIt() {
        #expect(DeckCard.noReleaseLine(tracked: false) == "We don't track this game's updates yet")
    }

    @Test func theTwoStatesStayDistinctAndNeverEchoTheName() {
        let game = "Roblox"
        let lines = [true, false].map { DeckCard.noReleaseLine(tracked: $0) }
        #expect(lines[0] != lines[1])
        #expect(lines.allSatisfy { !$0.contains(game) })
    }
}
