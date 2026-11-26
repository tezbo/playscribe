import Testing
@testable import Playscribe

/// R-7 (Terry, 26 Nov): a rail fades only an edge that has more content beyond it.
struct RailEdgesTests {
    @Test func atRestOnlyTheTrailingEdgeFades() {
        #expect(RailEdges.of(offset: 0, viewport: 400, content: 900) == RailEdges(leading: false, trailing: true))
    }
    @Test func scrolledToTheMiddleBothFade() {
        #expect(RailEdges.of(offset: 200, viewport: 400, content: 900) == RailEdges(leading: true, trailing: true))
    }
    @Test func atTheEndOnlyTheLeadingEdgeFades() {
        #expect(RailEdges.of(offset: 500, viewport: 400, content: 900) == RailEdges(leading: true, trailing: false))
    }
    @Test func aRailThatFitsFadesNowhere() {
        #expect(RailEdges.of(offset: 0, viewport: 400, content: 380) == RailEdges(leading: false, trailing: false))
    }
}
