import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// Iris on #515 (CM-1): under Reduce Motion the front cover is still, so two frames seconds apart are pixel-equal. The same two
/// frames with Reduce Motion off must differ, which proves the comparison would catch motion (a red-first control).
/// Time is set with the internal `qaMotionTime` clock and Reduce Motion with `qaReduceMotion`, the switches the stills use.
@MainActor
@Suite(.serialized)
struct CoverReduceMotionPixelTests {
    private let size = CGSize(width: 233, height: 339)   // the Closed cover at half size, scale 1

    /// A cover page whose key art passes the murky check, so Key-art motion would run on it.
    private func movingCard() throws -> (AppModel, DeckCard) {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "rm-\(UUID().uuidString).json"))
        m.resetToManyUpdatesDemo()
        let card = try #require(m.latestDeck.first { card in
            card.game.keyArtAsset.map { !KeyArtQuality.isMurky(asset: $0) } ?? false
        }, "a deck card with key art that moves")
        return (m, card)
    }

    private func frame(_ model: AppModel, _ card: DeckCard, at seconds: Double, reduceMotion: Bool) throws -> [UInt8] {
        let defaults = UserDefaults.standard
        defaults.set(seconds, forKey: "qaMotionTime")
        defaults.set(reduceMotion, forKey: "qaReduceMotion")
        defaults.set(CoverMotion.keyArt.rawValue, forKey: CoverMotion.key)
        let r = ImageRenderer(content: FrontCoverPage(card: card).environment(model).frame(width: size.width, height: size.height))
        r.scale = 1
        let cg = try #require(r.cgImage)
        var px = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                      bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        #expect(ok)
        return px
    }

    private func restore() {
        for key in ["qaMotionTime", "qaReduceMotion", CoverMotion.key] { UserDefaults.standard.removeObject(forKey: key) }
    }

    /// Count of channel values that differ by more than 1 (rendering noise), as a share of all channels.
    private func changed(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        let n = zip(a, b).reduce(0) { $0 + (abs(Int($1.0) - Int($1.1)) > 1 ? 1 : 0) }
        return Double(n) / Double(a.count)
    }

    @Test func reduceMotionFramesSecondsApartArePixelEqual() throws {
        defer { restore() }
        let (m, card) = try movingCard()
        let early = try frame(m, card, at: 1, reduceMotion: true)
        let late = try frame(m, card, at: 6, reduceMotion: true)
        #expect(changed(early, late) == 0, "Reduce Motion: \(changed(early, late) * 100)% of the cover changed in 5 s")
    }

    @Test func withoutReduceMotionTheSameFramesDiffer() throws {
        defer { restore() }
        let (m, card) = try movingCard()
        let early = try frame(m, card, at: 1, reduceMotion: false)
        let late = try frame(m, card, at: 6, reduceMotion: false)
        #expect(changed(early, late) > 0.05, "Key-art motion: only \(changed(early, late) * 100)% changed in 5 s")
    }
}
