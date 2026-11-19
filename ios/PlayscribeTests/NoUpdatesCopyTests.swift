import Testing
@testable import Playscribe

/// Tabletop's "No updates yet" line promises to tell the reader only when the game is in their library: a game they are only
/// browsing (Add to library showing) has no alert to promise (Iris, #511 follow-up, 0.5.5).
struct NoUpdatesCopyTests {
    @Test func onlyALibraryGameInTabletopPromisesAnAlert() {
        #expect(NoUpdatesLine.checkedCopy(tabletop: true, inLibrary: true) == "No updates yet. We’ll tell you when the first one lands.")
        #expect(NoUpdatesLine.checkedCopy(tabletop: true, inLibrary: false) == "No updates yet.")
        #expect(NoUpdatesLine.checkedCopy(tabletop: false, inLibrary: true) == "No updates yet.")
        #expect(NoUpdatesLine.checkedCopy(tabletop: false, inLibrary: false) == "No updates yet.")
    }
}
