import Foundation
import Testing
import SwiftUI
@testable import Playscribe

/// Book: no text or control within 24 pt of the division band (CLAUDE.md, r054-book-gamepage-hinge-inset).
/// Frame dump on c70ca4d: the left page's rows ended 15 pt short of the band and the right page's text began 20 pt past it.
struct HingeInsetTests {
    private func ctx(_ pose: String) -> DuoContext {
        let size = CGSize(width: 951, height: 670)
        let fold = pose == "book" ? CGRect(x: 455.5, y: 0, width: 40, height: 669) : nil
        return DuoReader<EmptyView>.context(size: size, compact: false, division: fold, occlusions: [])
    }

    @Test("Book: the edge facing the hinge keeps 24 pt, the edge facing the screen keeps its own inset")
    func bookFacingHinge() {
        let book = ctx("book")
        #expect(book.pose == .book)
        #expect(book.hingeInset(16, facingHinge: true) == 24)
        #expect(book.hingeInset(20, facingHinge: true) == 24)
        #expect(book.hingeInset(16, facingHinge: false) == 16)
        // A page that already insets more than 24 pt keeps it.
        #expect(book.hingeInset(32, facingHinge: true) == 32)
    }

    @Test("Every other pose keeps the page's own inset")
    func otherPoses() {
        let flat = ctx("flat")
        #expect(flat.hingeInset(16, facingHinge: true) == 16)
        #expect(flat.hingeInset(20, facingHinge: true) == 20)
    }

    @Test("Left page ends 24 pt clear of the band, right page starts 24 pt past it")
    func clearOfBand() {
        let book = ctx("book")
        let band = try! #require(book.division)
        // The panes meet the band exactly; the page's own padding sits inside them.
        #expect(band.minX - book.hingeInset(16, facingHinge: true) <= band.minX - 24)
        #expect(band.maxX + book.hingeInset(20, facingHinge: true) >= band.maxX + 24)
    }
}
