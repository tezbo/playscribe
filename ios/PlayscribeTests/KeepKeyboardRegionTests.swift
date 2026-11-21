import Testing
import CoreGraphics
@testable import Playscribe

/// The Library search clear button keeps the keyboard up through a registered frame, decided at touch start. A tap just outside
/// the frame is still an outside tap (it dismisses), and a removed frame keeps nothing.
@Suite(.serialized) struct KeepKeyboardRegionTests {
    @Test func insideKeepsOutsideDismissesRemovedKeepsNothing() {
        let id = "test-region"
        KeyboardState.setKeepRegion(id, CGRect(x: 300, y: 100, width: 44, height: 44))
        #expect(KeyboardState.keepRegionContains(CGPoint(x: 320, y: 120)))
        #expect(!KeyboardState.keepRegionContains(CGPoint(x: 299, y: 120)))
        #expect(!KeyboardState.keepRegionContains(CGPoint(x: 320, y: 145)))
        KeyboardState.setKeepRegion(id, CGRect(x: 10, y: 10, width: 44, height: 44))
        #expect(!KeyboardState.keepRegionContains(CGPoint(x: 320, y: 120)))
        #expect(KeyboardState.keepRegionContains(CGPoint(x: 20, y: 20)))
        KeyboardState.removeKeepRegion(id)
        #expect(!KeyboardState.keepRegionContains(CGPoint(x: 20, y: 20)))
    }
}
