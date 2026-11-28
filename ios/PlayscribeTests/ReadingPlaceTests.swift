import CoreGraphics
import Testing
@testable import Playscribe

/// 0.5.6 (Mac walk at 1c5ebfc, steps 5 and 6): a pose change keeps the section the reader is in.
struct ReadingPlaceTests {
    @Test("The reader is in the lowest section whose top has scrolled to or past the top of the view")
    func currentSection() {
        let tops: [String: CGFloat] = ["fixed": -420, "balance": -12, "allupdates": 310, "about": 900]
        #expect(ReadingPlace.current(tops) == "balance")
    }

    @Test("A section whose top sits exactly at the top of the view is the one being read")
    func sectionAtTop() {
        #expect(ReadingPlace.current(["fixed": -300, "allupdates": 0.5, "about": 600]) == "allupdates")
    }

    @Test("Above the first section there is no section to return to")
    func aboveFirst() {
        #expect(ReadingPlace.current(["fixed": 140, "about": 700]) == nil)
    }

    @Test("An anchor round-trips its section; an older pixel offset names none")
    func anchorRoundTrip() {
        #expect(ReadingPlace.mark(ReadingPlace.encode("mark-allupdates")) == "mark-allupdates")
        #expect(ReadingPlace.mark("812") == nil)
        #expect(ReadingPlace.mark(nil) == nil)
    }

    /// polish-pose-change-scroll-anchor: the list's place is the topmost row plus how far into it the reader is, so a pose change
    /// that reflows the rows lands on the same row within 8 pt (the old raw offset landed 30 to 130 pt off).
    @Test func listPlaceIsTheTopmostRowAndTheDistanceIntoIt() {
        let tops: [String: CGFloat] = ["row-a": -310, "row-b": -42, "row-c": 96, "row-d": 280]
        let a = ReadingPlace.rowPlace(tops, slack: 0)
        #expect(a == "row:row-b@42")
        #expect(ReadingPlace.parseRowPlace(a) == ReadingPlace.RowPlace(id: "row-b", within: 42))
    }

    @Test func listPlaceIgnoresMarksThatAreNotRows() {
        #expect(ReadingPlace.rowPlace(["balance": -5, "row-x": -20], slack: 0) == "row:row-x@20")
        #expect(ReadingPlace.rowPlace(["balance": -5], slack: 0) == nil)
        #expect(ReadingPlace.rowPlace(["row-x": 60], slack: 0) == nil, "above the first row there is no row place")
    }

    @Test func listPlaceParsesOnlyItsOwnStrings() {
        #expect(ReadingPlace.parseRowPlace("mark:balance") == nil)
        #expect(ReadingPlace.parseRowPlace("412") == nil)
        #expect(ReadingPlace.parseRowPlace("row:row-x@-3") == ReadingPlace.RowPlace(id: "row-x", within: 0))
        #expect(ReadingPlace.parseRowPlace("row:row-x@") == nil)
    }
}
