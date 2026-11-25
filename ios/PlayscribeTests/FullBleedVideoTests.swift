import CoreGraphics
import SwiftUI
import Testing
@testable import Playscribe

/// R-13, bug-071: our own full-screen video. Fit only, as large as the whole screen allows with a black band of at least 44 pt
/// above and below for our controls (YouTube RMF: nothing of ours in front of the player), centred. Offered everywhere but
/// Tabletop.
struct FullBleedVideoTests {
    @Test func offeredEverywhereButTabletop() {
        #expect(FullBleedVideo.offered(in: .closed))
        #expect(FullBleedVideo.offered(in: .flat))
        #expect(FullBleedVideo.offered(in: .book), "bug-071 spec: Book uses the whole inner screen across the fold")
        #expect(!FullBleedVideo.offered(in: .tabletop), "Tabletop: the standing half is already the stage, and the mirror stays there")
    }

    /// The card's poses: Closed landscape 678 x 466 has a natural 42 pt band, so the picture shrinks just enough to leave 44
    /// (672 x 378); Open flat landscape and Book (951 x 669) keep the full width with 67 pt bands.
    @Test(arguments: [(CGSize(width: 678, height: 466), CGSize(width: 672, height: 378), CGFloat(44)),
                      (CGSize(width: 951, height: 669), CGSize(width: 951, height: 534.9), CGFloat(67))])
    func fitMatchesTheSpec(screen: CGSize, picture: CGSize, band: CGFloat) {
        let f = FullBleedVideo.fit(in: screen)
        #expect(abs(f.width - picture.width) < 1, "\(f)")
        #expect(abs(f.height - picture.height) < 1, "\(f)")
        #expect(abs(f.minY - band) < 1, "top band \(f.minY)")
        #expect(abs((screen.height - f.maxY) - band) < 1, "bottom band")
        #expect(f.minY >= FullBleedVideo.minBand - 0.01 && screen.height - f.maxY >= FullBleedVideo.minBand - 0.01)
        #expect(abs(f.width / f.height - 16 / 9) < 0.001)
        #expect(abs(f.midX - screen.width / 2) < 0.01 && abs(f.midY - screen.height / 2) < 0.01)
    }

    @Test func fitTouchesTwoOppositeEdgesWhenTheBandsAreRoomy() {
        // Open flat landscape: the picture runs edge to edge across the width (AC 1).
        let f = FullBleedVideo.fit(in: CGSize(width: 951, height: 669))
        #expect(f.minX == 0 && f.maxX == 951)
    }

    @Test func portraitFillsTheWidth() {
        // Portrait (rotation lock): full width, the bands are the large remainders.
        let f = FullBleedVideo.fit(in: CGSize(width: 466, height: 678))
        #expect(f.width == 466)
        #expect(abs(f.midY - 339) < 0.01)
    }

    @Test func occlusionOverThePictureWidensItsBand() {
        // A camera housing at the top centre, 60 pt deep: the picture moves clear of it and stays centred.
        let housing = CGRect(x: 300, y: 0, width: 80, height: 60)
        let f = FullBleedVideo.fit(in: CGSize(width: 678, height: 466), avoiding: [housing])
        #expect(!f.intersects(housing))
        #expect(f.minY >= 60 - 0.01 && 466 - f.maxY >= 60 - 0.01)
        // A side housing in landscape narrows the picture instead.
        let side = CGRect(x: 0, y: 150, width: 30, height: 120)
        let g = FullBleedVideo.fit(in: CGSize(width: 951, height: 669), avoiding: [side])
        #expect(!g.intersects(side) && g.minX >= 30 - 0.01)
    }

    @Test func emptyAreaGivesNoFrame() {
        #expect(FullBleedVideo.fit(in: .zero) == .zero)
    }

    /// specBands: every control row is in a band, off the picture, inside the safe leading and trailing insets (Closed
    /// landscape measured 84 pt on the camera side, run 45706235978).
    @Test(arguments: [(CGSize(width: 678, height: 466), EdgeInsets()),
                      (CGSize(width: 678, height: 466), EdgeInsets(top: 0, leading: 84, bottom: 21, trailing: 0)),
                      (CGSize(width: 466, height: 678), EdgeInsets(top: 54, leading: 0, bottom: 34, trailing: 0)),
                      (CGSize(width: 951, height: 669), EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0))])
    func controlRowsSitInTheBandsNeverOnThePicture(screen: CGSize, safe: EdgeInsets) {
        let f = FullBleedVideo.fit(in: screen)
        let l = FullScreenBands.layout(picture: f, screen: screen, safe: safe, division: nil)
        #expect(l.top.maxY <= f.minY + 0.01, "top row \(l.top) is on the picture \(f)")
        #expect(l.transport.minY >= f.maxY - 0.01 && l.transport.maxY <= screen.height + 0.01, "bottom row \(l.transport)")
        #expect(l.top.minY >= 0 && l.top.minX >= safe.leading && l.top.maxX <= screen.width - safe.trailing)
        #expect(l.top.height == 44 && l.transport.height == 44 && l.timeline == nil)
    }

    /// Book: transport and title on the leading page, the timeline on the trailing page, nothing within 8 pt of the division,
    /// and the guard (the division itself) is all that covers the fold.
    @Test func bookSplitsTheRowsAroundTheFold() {
        let screen = CGSize(width: 951, height: 669), fold = CGRect(x: 455, y: 0, width: 40, height: 669)
        let f = FullBleedVideo.fit(in: screen)
        let l = FullScreenBands.layout(picture: f, screen: screen, safe: EdgeInsets(), division: fold)
        let clear = fold.insetBy(dx: -FullScreenBands.foldClearance, dy: 0)
        for r in [l.top, l.transport, l.timeline ?? .null] {
            #expect(!r.isNull && !r.intersects(clear), "\(r) is within 8 pt of the fold")
            #expect(!r.intersects(f), "\(r) is on the picture")
        }
        #expect(l.transport.maxX <= fold.minX && (l.timeline?.minX ?? 0) >= fold.maxX)
    }
}
