import XCTest
@testable import Playscribe

/// G-8 (Iris, r054): a capped title ends on a whole word followed by "…", never a cut word.
final class WholeWordTextTests: XCTestCase {
    func testEveryVariantIsTheWholeTextOrAWholeWordPrefixWithEllipsis() {
        let title = "The Grand Autumn Rebalancing, Quality of Life and Stability Update, Including Every Hotfix Since Launch"
        let words = title.split(separator: " ").map(String.init)
        let variants = WholeWordText.variants(of: title)
        XCTAssertEqual(variants.first, title)
        XCTAssertEqual(variants.count, words.count, "the whole text plus one shorter variant per dropped word")
        for v in variants.dropFirst() {
            XCTAssertTrue(v.hasSuffix("\u{2026}"), "a shortened title ends with an ellipsis")
            let kept = String(v.dropLast())
            XCTAssertTrue(title.hasPrefix(kept + " "), "\(kept): the cut falls on a word boundary")
        }
    }

    func testOneWordTitleIsNeverCut() {
        XCTAssertEqual(WholeWordText.variants(of: "Hotfix"), ["Hotfix"])
    }
}
