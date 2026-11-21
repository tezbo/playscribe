import CoreGraphics
import SwiftUI
import Testing
@testable import Playscribe

/// R-11, Iris on #556 (reflection-0.6 spec 4 and 8): a pure white 16:9 frame through the mirror pipeline, read as pixels over
/// black. The crop and flip are the same geometry as `VideoMirrorStrip` (`VideoReflection.replicaFrame`, then a vertical flip);
/// the finish is the stage's own `mirrorFinish`. The live replica itself is the render server's and is checked on the Mac and
/// on Terry's Duo, not here.
@MainActor
struct MirrorPixelTests {
    /// The Tabletop video: the lower half's width beside the rail, 16:9.
    private let video = CGSize(width: 613, height: 613 * 9 / 16)

    /// The strip for a white frame, cropped to its bottom `band` rows and flipped, finished as on the stage, over black.
    private func strip(band: CGFloat, controlsShown: Bool) -> some View {
        let r = VideoReflection.replicaFrame(video: video, band: band)
        return ZStack(alignment: .topLeading) {
            Color.black
            ZStack(alignment: .topLeading) {
                Color.white.frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
            }
            .frame(width: video.width, height: band, alignment: .topLeading)
            .clipped()
            .scaleEffect(x: 1, y: -1)
            .mirrorFinish(controlsShown: controlsShown)
        }
        .frame(width: video.width, height: band)
        .environment(\.colorScheme, .dark)
    }

    /// One grey value per pixel row (0 to 255), down the middle column.
    private func column(_ view: some View) throws -> [Int] {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "the strip rendered")
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let x = w / 2
        // The context's first row in memory is the image's top row.
        return (0..<h).map { y in Int(px[(y * w + x) * 4 + 1]) }
    }

    @Test(arguments: [(CGFloat(456), false), (CGFloat(456), true), (CGFloat(1000), false), (CGFloat(1000), true)])
    func whiteFrameThroughTheMirror(lowerHalf: CGFloat, shown: Bool) throws {
        let band = VideoReflection.band(lowerHalf: lowerHalf)
        // The band: at most 120 pt and 15% of the lower half.
        #expect(band == min(120, lowerHalf * 0.15))
        let rows = try column(strip(band: band, controlsShown: shown))
        print("MirrorPixelTests lowerHalf \(lowerHalf) shown \(shown) band \(band): rows \(rows.count) first \(rows.first ?? -1) last \(rows.last ?? -1) column \(rows)")
        #expect(abs(CGFloat(rows.count) - band) <= 1, "the strip is the band tall: \(rows.count) rows for \(band) pt")
        let edge = VideoReflection.edgeOpacity(controlsShown: shown)
        let first = try #require(rows.first)
        // Hidden: 30% to 55% of white (Iris). Shown: at least 30/35 of the 20% edge, and never above it.
        let floor = shown ? edge * 30 / 35 : 0.30
        #expect(Double(first) >= floor * 255, "first row \(first) reaches \(floor) of white (edge \(edge))")
        #expect(Double(first) <= edge * 255 + 1, "first row \(first) stays at or under the edge strength \(edge)")
        #expect(try #require(rows.last) <= 1, "the last row reads 0")
        for i in 1..<rows.count {
            // Monotonic down the band (1/255 allowed for rounding), and no step over 4/255.
            #expect(rows[i] <= rows[i - 1] + 1, "row \(i) \(rows[i]) does not rise over row \(i - 1) \(rows[i - 1])")
            #expect(abs(rows[i] - rows[i - 1]) <= 4, "row \(i) steps \(rows[i - 1]) to \(rows[i])")
        }
    }
}
