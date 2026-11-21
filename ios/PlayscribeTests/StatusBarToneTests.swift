import CoreGraphics
import UIKit
import Testing
@testable import Playscribe

/// bug-064: the status bar is light while art is under it, dark once the art's bottom edge passes the bar, with 8 pt of hysteresis.
struct StatusBarToneTests {
    let bar: CGFloat = 54

    private func art(bottom: CGFloat) -> CGRect { CGRect(x: 0, y: bottom - 300, width: 400, height: 300) }

    @Test func lightWhileArtIsUnderTheBar() {
        #expect(StatusBarTone.isLight(current: false, barBottom: bar, art: [CGRect(x: 0, y: 0, width: 400, height: 300)], coverUp: false))
    }

    @Test func lightWhenArtStartsPartWayDownTheBar() {
        // Closed portrait: the header art starts under the clock, not at the screen's top edge (Mac at d7656024, 3.4:1 dark glyphs).
        #expect(StatusBarTone.isLight(current: false, barBottom: bar, art: [CGRect(x: 0, y: 23, width: 400, height: 180)], coverUp: false))
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

    @Test func alwaysLightOnADarkPage() {
        // G-11: the scheme can change at runtime; on a dark page the bar is light whatever is under it.
        #expect(StatusBarTone.isLight(current: false, barBottom: bar, art: [], coverUp: false, pageLight: false))
        #expect(StatusBarTone.isLight(current: true, barBottom: bar, art: [art(bottom: bar)], coverUp: false, pageLight: false))
    }

    @Test(arguments: [CGFloat(47), 54, 59, 62])
    func darkPageIsLightWhateverTheBar(bar: CGFloat) {
        // The bar heights of the poses (Closed, Book, Open, Tabletop): the decision never uses the pose, and dark is always light.
        for art in [[], [CGRect(x: 0, y: 0, width: 400, height: 300)], [CGRect(x: 0, y: bar - 10, width: 400, height: 20)]] {
            #expect(StatusBarTone.isLight(current: false, barBottom: bar, art: art, coverUp: false, pageLight: false))
            #expect(StatusBarTone.isLight(current: true, barBottom: bar, art: art, coverUp: false, pageLight: false))
        }
    }
}

/// Quinn's gate on #567: while the app window is dark no tone window exists, so the bar comes from the app's window exactly as
/// before; G-11 can switch the scheme at runtime, so dark → light → dark is checked on a live scene.
@MainActor
struct StatusBarToneWindowTests {
    private var scene: UIWindowScene? { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first }

    @Test func darkNeverMakesTheWindow() throws {
        let scene = try #require(scene)
        let tone = StatusBarTone()
        tone.attach(to: scene)
        tone.setPageLight(false)
        tone.setCover(true)
        tone.setCover(false)
        tone.report(UUID(), frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(!tone.hasWindow)
        #expect(!tone.windowShown)
        #expect(tone.style == .lightContent)
    }

    @Test func darkToLightToDark() throws {
        let scene = try #require(scene)
        let tone = StatusBarTone()
        tone.attach(to: scene)
        #expect(!tone.hasWindow)

        tone.setPageLight(true)
        #expect(tone.windowShown)
        #expect(tone.style == .darkContent, "light page, no art under the bar: dark glyphs over cream")
        let art = UUID()
        tone.report(art, frame: CGRect(x: 0, y: 0, width: scene.coordinateSpace.bounds.width, height: 300))
        // The test host may run with no status bar (height 0); the art rule itself is covered above with fixed bar heights.
        if tone.barBottom > 0 { #expect(tone.style == .lightContent, "light page, art under the bar") }

        tone.setPageLight(false)
        #expect(!tone.windowShown, "dark again: the window is hidden and the app's window sets the bar")
        #expect(tone.style == .lightContent)

        tone.setPageLight(true)
        #expect(tone.windowShown)
        tone.report(art, frame: nil)
        #expect(tone.style == .darkContent)
        tone.setPageLight(false)
        #expect(!tone.windowShown)
    }
}
