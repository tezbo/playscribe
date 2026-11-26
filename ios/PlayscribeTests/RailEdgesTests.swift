import XCTest
@testable import Playscribe

/// R-7 (Terry, 26 Nov): a rail fades only an edge that has more content beyond it.
final class RailEdgesTests: XCTestCase {
    func testAtRestOnlyTheTrailingEdgeFades() {
        XCTAssertEqual(RailEdges.of(offset: 0, viewport: 400, content: 900), RailEdges(leading: false, trailing: true))
    }
    func testScrolledToTheMiddleBothFade() {
        XCTAssertEqual(RailEdges.of(offset: 200, viewport: 400, content: 900), RailEdges(leading: true, trailing: true))
    }
    func testAtTheEndOnlyTheLeadingEdgeFades() {
        XCTAssertEqual(RailEdges.of(offset: 500, viewport: 400, content: 900), RailEdges(leading: true, trailing: false))
    }
    func testARailThatFitsFadesNowhere() {
        XCTAssertEqual(RailEdges.of(offset: 0, viewport: 400, content: 380), RailEdges(leading: false, trailing: false))
    }
}
