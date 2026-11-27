import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// s-06-brand-swap (Warm refresh, gamebook/brand/identity/final): the mark's lit and rest states, the ember text pairs, and no
/// trace of the previous mark's assets in the app.
@MainActor
struct BrandMarkTests {
    /// The spark glows while any update is unread and rests when caught up.
    @Test func markIsLitOnlyWithUnread() {
        #expect(BrandMark.isLit(totalUnread: 1))
        #expect(BrandMark.isLit(totalUnread: 12))
        #expect(!BrandMark.isLit(totalUnread: 0))
    }

    /// Small ember text: #A04E0D on the light grounds and #FFB04F on ink, both 4.5:1 or better.
    @Test func emberTextPairsPassAA() {
        let lightEmber = PlayscribeRole.resolved(PlayscribeRole.newTextSpec, light: true)
        #expect(Contrast.ratio(lightEmber, UIColor(hex: 0xA04E0D)) < 1.01, "light ember text is #A04E0D")
        for surface in [PlayscribeRole.bgSpec, PlayscribeRole.cardSpec] {
            let r = Contrast.ratio(lightEmber, PlayscribeRole.resolved(surface, light: true))
            #expect(r >= 4.5, "light \(surface.name): \(r)")
        }
        let darkEmber = PlayscribeRole.resolved(PlayscribeRole.newTextSpec, light: false)
        #expect(Contrast.ratio(darkEmber, UIColor(hex: 0xFFB04F)) < 1.01, "dark ember text is #FFB04F")
        let ink = UIColor(PlayscribeColor.ink900)
        #expect(Contrast.ratio(darkEmber, ink) >= 4.5, "dark ember on ink: \(Contrast.ratio(darkEmber, ink))")
    }

    /// The previous mark's files and names are gone from the app source.
    @Test func oldMarkIsGone() throws {
        let ui = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI")
        let files = try FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        for file in files {
            let src = try String(contentsOf: file, encoding: .utf8)
            for old in ["mark-dim", "wordmark-mono", "24 × 48 grid", ".brand1", ".brand2", ".brand3"] {
                #expect(!src.contains(old), "\(file.lastPathComponent) still refers to the previous mark: \(old)")
            }
        }
    }
}
