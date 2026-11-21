import CoreGraphics
import Testing
@testable import Playscribe

/// R-13: our own full-screen video. Offered in Closed and Open only, and the video is 16:9, as large as the window allows, centred.
struct FullBleedVideoTests {
    @Test func offeredInClosedAndOpenOnly() {
        #expect(FullBleedVideo.offered(in: .closed))
        #expect(FullBleedVideo.offered(in: .flat))
        #expect(!FullBleedVideo.offered(in: .book), "Book: a full-bleed video would cross the hinge")
        #expect(!FullBleedVideo.offered(in: .tabletop), "Tabletop: the standing half is already the stage, and the mirror stays there")
    }

    @Test func landscapeFillsTheHeight() {
        // Closed landscape, wider than 16:9: full height, pillarboxed.
        let f = FullBleedVideo.frame(in: CGSize(width: 900, height: 400))
        #expect(f.height == 400)
        #expect(abs(f.width - 400 * 16 / 9) < 0.01)
        #expect(abs(f.midX - 450) < 0.01)
    }

    @Test func portraitFillsTheWidth() {
        // Closed or Open portrait: full width, letterboxed and centred.
        let f = FullBleedVideo.frame(in: CGSize(width: 400, height: 860))
        #expect(f.width == 400)
        #expect(abs(f.height - 225) < 0.01)
        #expect(abs(f.midY - 430) < 0.01)
    }

    @Test func emptyAreaGivesNoFrame() {
        #expect(FullBleedVideo.frame(in: .zero) == .zero)
    }

    @Test func exitSitsInTheMarginWhenThereIsRoom() {
        // Portrait: a 225 pt video centred in 860 pt leaves far more than 52 pt above it.
        let portrait = FullBleedVideo.frame(in: CGSize(width: 400, height: 860))
        #expect(FullBleedVideo.exitInMargin(video: portrait, safeTop: 54))
        // Landscape: the video fills the height, so there is no margin; the button goes top leading and fades.
        let landscape = FullBleedVideo.frame(in: CGSize(width: 900, height: 400))
        #expect(!FullBleedVideo.exitInMargin(video: landscape, safeTop: 0))
        // Exactly 52 pt counts; 51 does not.
        #expect(FullBleedVideo.exitInMargin(video: CGRect(x: 0, y: 106, width: 10, height: 10), safeTop: 54))
        #expect(!FullBleedVideo.exitInMargin(video: CGRect(x: 0, y: 105, width: 10, height: 10), safeTop: 54))
    }
}
