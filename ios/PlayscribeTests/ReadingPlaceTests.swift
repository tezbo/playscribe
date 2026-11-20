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
}
