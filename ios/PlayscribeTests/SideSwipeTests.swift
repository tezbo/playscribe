import CoreGraphics
import Testing
@testable import Playscribe

/// N-1 and N-9: only a far, mainly sideways swipe dismisses the alerts and keep-current cards; a vertical drag is the page's (#635).
struct SideSwipeTests {
    @Test func onlyAFarMainlySidewaysSwipeDismisses() {
        #expect(SideSwipe.dismisses(CGPoint(x: -120, y: 10)))
        #expect(SideSwipe.dismisses(CGPoint(x: 90, y: -30)))
        #expect(!SideSwipe.dismisses(CGPoint(x: 40, y: 0)))     // too short
        #expect(!SideSwipe.dismisses(CGPoint(x: 10, y: -300)))  // a page scroll
        #expect(!SideSwipe.dismisses(CGPoint(x: 100, y: 80)))   // diagonal
    }
}
