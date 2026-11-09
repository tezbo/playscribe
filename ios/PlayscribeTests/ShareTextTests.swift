import Testing
import Foundation
@testable import Playscribe

/// Share text: no stray markup, no blank gaps, no doubled full stops; the link opens the update.
struct ShareTextTests {
    @Test func lineStripsMarkupAndDoubledStops() {
        #expect(ShareText.line("Improved ladder interaction animations..") == "Improved ladder interaction animations.")
        #expect(ShareText.line("[*]Fixed  a crash\n\n[/*]") == "Fixed a crash")
    }

    @Test func linkIsUniversalAndEncoded() {
        #expect(ShareText.link(gameID: "witcher-3", releaseID: "5.01")?.absoluteString == "https://playscribe.codeconnectors.co/r/witcher-3/5.01")
        #expect(ShareText.link(gameID: "g", releaseID: "a b")?.absoluteString == "https://playscribe.codeconnectors.co/r/g/a%20b")
    }
}
