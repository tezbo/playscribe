import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// bug-text-on-bright-art, Tabletop stage (Iris on #514): the stage scrim has no edge on the art. It spans the full stage width
/// (no side edge), eases in from clear at its top (no top edge) and holds to the stage's bottom (no bottom edge). Rendered over
/// pure white, the worst case, with a caption block far narrower than the stage, as "Coming soon" with a short name is.
@MainActor
struct BrightArtScrimTests {
    private let stage = CGSize(width: 400, height: 300)
    private let block = CGSize(width: 120, height: 60)

    private func render(fullBleed: Bool) throws -> CGImage {
        let view = Color.white
            .frame(width: stage.width, height: stage.height)
            .overlay(alignment: .bottomLeading) {
                Color.clear.frame(width: block.width, height: block.height)
                    .brightArtScrim(0.75, fullBleed: fullBleed)
            }
        let r = ImageRenderer(content: view)
        r.scale = 1
        return try #require(r.cgImage)
    }

    /// Grey level 0...255 at a point in points (scale 1), from the top-left.
    private func grey(_ cg: CGImage, _ x: Int, _ y: Int) throws -> Int {
        var rgba = [UInt8](repeating: 0, count: 4)
        let ctx = try #require(CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return (Int(rgba[0]) + Int(rgba[1]) + Int(rgba[2])) / 3
    }

    /// Mean grey of a patch `w` wide centred on x, over rows y-1...y+1 clamped to the image. A gradient is dithered, so one
    /// pixel can sit a level or two off its neighbour; an edge moves the whole patch (#558 CI: a single-pixel read failed by dither).
    private func patch(_ cg: CGImage, _ x: Int, _ y: Int, w: Int = 5) throws -> Int {
        var sum = 0, n = 0
        for yy in max(0, y - 1)...min(cg.height - 1, y + 1) {
            for xx in max(0, x - w / 2)...min(cg.width - 1, x + w / 2) { sum += try grey(cg, xx, yy); n += 1 }
        }
        return sum / n
    }

    @Test func stageScrimSpansTheFullWidth() throws {
        let cg = try render(fullBleed: true)
        let h = Int(stage.height)
        // Behind the block, in the ramp above it, and at the stage's bottom row: the far right matches the far left.
        for y in [h - 30, h - Int(block.height) - 20, h - 1] {
            let left = try patch(cg, 4, y), right = try patch(cg, Int(stage.width) - 5, y)
            #expect(abs(left - right) <= 2, "row \(y): left \(left), right \(right) (no side edge)")
        }
    }

    @Test func stageScrimEasesInAndHoldsToTheBottom() throws {
        let cg = try render(fullBleed: true)
        let h = Int(stage.height)
        let top = h - Int(block.height) - Int(BrightArtScrim.stageRamp)
        // Clear above the ramp, so the art is untouched there.
        #expect(try grey(cg, 200, top - 4) >= 253, "clear above the ramp")
        // Darkens steadily down the ramp, never by a visible step (no top edge).
        var last = try grey(cg, 200, top)
        for y in top + 1...(h - Int(block.height)) {
            let g = try grey(cg, 200, y)
            #expect(g <= last + 1, "row \(y) is no lighter than the row above (\(g) after \(last))")
            #expect(last - g <= 12, "row \(y): a step of \(last - g) is an edge")
            last = g
        }
        // Full strength from the block's top to the stage's bottom: 75% black over white is about 64.
        for y in [h - Int(block.height) + 2, h - 30, h - 1] {
            let g = try grey(cg, 200, y)
            #expect(g <= 70, "row \(y) at full strength (\(g))")
        }
    }

    /// The boxed scrim the deck cards keep: it stops at the block's sides, which is the edge Iris saw on the stage. This pins
    /// the difference, so the stage cannot slip back to it.
    @Test func boxedScrimStopsAtTheBlockSides() throws {
        let cg = try render(fullBleed: false)
        let y = Int(stage.height) - 30
        #expect(try grey(cg, Int(stage.width) - 3, y) >= 250, "the boxed scrim leaves the far right of the stage clear")
    }
}
