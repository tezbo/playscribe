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

    @Test func safeSidesKeepThePictureIn() {
        let f = FullBleedVideo.fit(in: CGSize(width: 951, height: 669), sides: 40)
        #expect(f.minX >= 40 - 0.01 && f.maxX <= 911 + 0.01)
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

    /// Exit is in the band above the picture, inside the safe area, in every pose's real insets.
    @Test(arguments: [(CGSize(width: 678, height: 466), EdgeInsets()),
                      (CGSize(width: 678, height: 466), EdgeInsets(top: 0, leading: 47, bottom: 21, trailing: 47)),
                      (CGSize(width: 466, height: 678), EdgeInsets(top: 54, leading: 0, bottom: 34, trailing: 0)),
                      (CGSize(width: 951, height: 669), EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0))])
    func exitSitsInTheTopBandNeverOnThePicture(screen: CGSize, safe: EdgeInsets) {
        let f = FullBleedVideo.fit(in: screen, safeTop: safe.top, sides: max(safe.leading, safe.trailing))
        let exit = FullBleedVideo.exitFrame(picture: f, safe: safe)
        #expect(exit.maxY <= f.minY + 0.01, "Exit \(exit) is on the picture \(f)")
        #expect(exit.minY >= safe.top - 0.01 && exit.minX >= safe.leading)
        #expect(exit.width == 44 && exit.height == 44)
    }
}
