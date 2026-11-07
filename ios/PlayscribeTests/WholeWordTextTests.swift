import Foundation
import Testing
@testable import Playscribe

/// G-8 (Iris, r054): a capped title ends on a whole word followed by "…", never a cut word.
@MainActor
struct WholeWordTextTests {
    @Test func everyVariantIsTheWholeTextOrAWholeWordPrefixWithEllipsis() {
        let title = "The Grand Autumn Rebalancing, Quality of Life and Stability Update, Including Every Hotfix Since Launch"
        let words = title.split(separator: " ").map(String.init)
        let variants = WholeWordText.variants(of: title)
        #expect(variants.first == title)
        #expect(variants.count == words.count, "the whole text plus one shorter variant per dropped word")
        for v in variants.dropFirst() {
            #expect(v.hasSuffix("\u{2026}"), "a shortened title ends with an ellipsis")
            let kept = String(v.dropLast())
            #expect(title.hasPrefix(kept + " "), "\(kept): the cut falls on a word boundary")
        }
    }

    @Test func oneWordTitleIsNeverCut() {
        #expect(WholeWordText.variants(of: "Hotfix") == ["Hotfix"])
    }

    /// A word wider than the column wraps by character (a lone comma can start a line), so the cut lands before it.
    @Test func variantKeepingAWordWiderThanTheColumnIsDropped() {
        let title = "The Grand Autumn Rebalancing, Quality of Life"
        let widths: [Int: CGFloat] = [0: 30, 1: 50, 2: 60, 3: 140, 4: 80, 5: 20, 6: 40]
        let fit = WholeWordText.fittingVariants(of: title, wordWidths: widths, available: 100)
        #expect(fit == ["The Grand Autumn\u{2026}", "The Grand\u{2026}", "The\u{2026}"])
        #expect(fit.allSatisfy { !$0.contains("Rebalancing") })
    }

    /// When even the first word is wider than the column, the shortest variant is still shown (never blank, never a loop).
    @Test func whenNoVariantFitsTheShortestIsKept() {
        let widths: [Int: CGFloat] = [0: 300, 1: 40, 2: 40]
        #expect(WholeWordText.fittingVariants(of: "Unbreakable Is Long", wordWidths: widths, available: 100) == ["Unbreakable\u{2026}"])
    }

    @Test func unmeasuredWidthsKeepEveryVariant() {
        let title = "One Two Three"
        #expect(WholeWordText.fittingVariants(of: title, wordWidths: [:], available: 0) == WholeWordText.variants(of: title))
    }
}
