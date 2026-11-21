import CoreGraphics
import Testing
@testable import Playscribe

/// bug-064: the status bar is light while art is under it, dark once the art's bottom edge passes the bar, with 8 pt of hysteresis.
struct StatusBarToneTests {
    let bar: CGFloat = 54

    private func art(bottom: CGFloat) -> CGRect { CGRect(x: 0, y: bottom - 300, width: 400, height: 300) }

    @Test func lightWhileArtIsUnderTheBar() {
        #expect(StatusBarTone.isLight(current: false, barBottom: bar, art: [CGRect(x: 0, y: 0, width: 400, height: 300)], coverUp: false))
    }

    @Test func darkOverThePageWithNoArt() {
        #expect(!StatusBarTone.isLight(current: true, barBottom: bar, art: [], coverUp: false))
        // Art lower on the page, not reaching the bar's top, does not count.
        #expect(!StatusBarTone.isLight(current: false, barBottom: bar, art: [CGRect(x: 0, y: 120, width: 400, height: 300)], coverUp: false))
    }

    @Test func goesDarkOnceTheArtsEdgePassesTheBar() {
        #expect(StatusBarTone.isLight(current: true, barBottom: bar, art: [art(bottom: bar + 1)], coverUp: false))
        #expect(!StatusBarTone.isLight(current: true, barBottom: bar, art: [art(bottom: bar)], coverUp: false))
    }

    @Test func comesBackLightOnlyEightPointsLater() {
        // Dark now: the edge back at the bar, or up to 8 pt below it, keeps it dark (no flicker on a resting scroll).
        for bottom in [bar + 1, bar + 4, bar + 8] {
            #expect(!StatusBarTone.isLight(current: false, barBottom: bar, art: [art(bottom: bottom)], coverUp: false), "bottom \(bottom)")
        }
        #expect(StatusBarTone.isLight(current: false, barBottom: bar, art: [art(bottom: bar + 9)], coverUp: false))
    }

    @Test func alwaysLightOverThePlayer() {
        #expect(StatusBarTone.isLight(current: false, barBottom: bar, art: [], coverUp: true))
        #expect(StatusBarTone.isLight(current: false, barBottom: 0, art: [], coverUp: true))
    }
}
