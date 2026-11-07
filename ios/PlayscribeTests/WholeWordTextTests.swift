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
}
