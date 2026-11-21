import Testing
import UIKit
@testable import Playscribe

/// Iris's header rule (21 Nov): the cover, the game page's art hero header and the Book contents header stay dark in both
/// modes, on `PlayscribeColor.heroGround`, with text from the fixed on-dark set. Headers and stages with no art use `bg`.
struct HeroGroundTests {
    private func source(_ name: String) throws -> String {
        let ui = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI").appendingPathComponent(name)
        return try String(contentsOf: ui, encoding: .utf8)
    }

    /// The on-dark set holds its floors on the hero ground: cream and cream secondary 4.5:1, the amber 3:1 as a graphic.
    @Test func onDarkSetReadsOnTheHeroGround() {
        let ground = UIColor(PlayscribeColor.heroGround)
        #expect(Contrast.ratio(UIColor(PlayscribeColor.onDarkText), ground) >= 4.5)
        #expect(Contrast.ratio(UIColor(PlayscribeColor.onDarkTextSecondary), ground) >= 4.5)
        #expect(Contrast.ratio(UIColor(PlayscribeColor.onDarkAccent), ground) >= 3)
    }

    /// No bare ink ground is left on these screens: the cover and the contents header name the hero ground, and the game
    /// page, its pinned bar, the bottom fade and the Open portrait bars are on bg.
    @Test(arguments: ["FrontCover.swift", "GamePageColumn.swift", "GameBookParts.swift", "RootView.swift", "SectionBar.swift", "UpdateRow.swift"])
    func noBareInkGround(file: String) throws {
        let src = try source(file)
        for ink in ["Color.ink0", "Color.ink1"] { #expect(!src.contains(ink), "\(file) still paints \(ink)") }
    }

    /// The cover's text and glyphs use only the on-dark set, never a text role or the bare 0.5 names.
    @Test func coverTextIsTheOnDarkSet() throws {
        let src = try source("FrontCover.swift")
        for name in ["PlayscribeRole.textPrimary", "PlayscribeRole.textSecondary", "PlayscribeColor.textPrimary",
                     "PlayscribeColor.textSecondary", "PlayscribeColor.accent"] {
            #expect(!src.contains(name), "FrontCover uses \(name)")
        }
    }

    /// The section bar reads the roles on bg and surface, and the on-dark set only on the hero ground (Book contents).
    @Test func sectionBarFollowsItsGround() throws {
        let src = try source("SectionBar.swift")
        let bar = String(src[..<(src.range(of: "struct PinnedSectionHeader")?.lowerBound ?? src.endIndex)])
        for name in ["PlayscribeColor.textPrimary", "PlayscribeColor.textSecondary", "PlayscribeColor.accent", "PlayscribeColor.ink700"] {
            #expect(!bar.contains(name), "SectionBar paints \(name) in both modes")
        }
        #expect(bar.contains("onDark ? PlayscribeColor.onDarkText : PlayscribeRole.textPrimary"))
        let book = try source("GameBookParts.swift")
        #expect(book.contains("PinnedSectionHeader(gameID: gameID, ink: PlayscribeRole.bg, inset: 0, style: .contents,"),
                "the Book contents header is on bg with role text (Iris: a dark strip between cream art and a cream page reads as a stripe)")
        #expect(try source("GamePageColumn.swift").contains("PinnedSectionHeader(gameID: gameID, ink: PlayscribeRole.bg,"))
    }
}
