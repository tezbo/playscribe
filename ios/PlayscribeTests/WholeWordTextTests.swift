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
            #expect(title.hasPrefix(kept), "\(kept): the cut falls on a word boundary")
            #expect(title.dropFirst(kept.count).first.map { $0 == " " || ",;:.".contains($0) } ?? false, "\(kept): the next character is a space or the trimmed mark")
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

    /// Punctuation stays attached to the word before it: words split on spaces only, so no word, and so no line the
    /// layout can start a variant with, begins with a comma or other mark (r061).
    @Test func punctuationStaysAttachedToItsWord() {
        let title = "The Grand Autumn Rebalancing, Quality of Life and Stability Update (Hotfix 2), Every Fix; Finally."
        let words = WholeWordText.words(of: title)
        #expect(words.contains("Rebalancing,"))
        #expect(words.allSatisfy { !(",.;:!?)".contains($0.first!)) }, "no word starts with punctuation")
        for v in WholeWordText.variants(of: title).dropFirst() {
            #expect(!v.dropLast().hasSuffix(" "), "no space before the ellipsis")
            #expect(!v.contains(" ,"), "a comma is never split from its word")
        }
    }

    /// Only the real column width decides: a word that fits one line in the column is kept, a wider one is not, with the
    /// widest kept word deciding for every variant (the comma case: "Rebalancing," is wider than "Rebalancing").
    @Test func theWordWithItsCommaDecidesNotTheWordAlone() {
        let title = "The Grand Autumn Rebalancing, Quality of Life"
        let widths: [Int: CGFloat] = [0: 30, 1: 50, 2: 60, 3: 101, 4: 80, 5: 20, 6: 40]   // "Rebalancing," = 101
        let fit = WholeWordText.fittingVariants(of: title, wordWidths: widths, available: 100)
        #expect(fit.first == "The Grand Autumn\u{2026}")
    }

    /// Iris (r061): the ellipsis follows the word, never a trailing , ; : . ("Rebalancing…", not "Rebalancing,…").
    @Test func trailingPunctuationIsTrimmedBeforeTheEllipsis() {
        let title = "The Grand Autumn Rebalancing, Quality of Life: Stability; Update. Hotfix"
        let variants = WholeWordText.variants(of: title)
        #expect(variants.contains("The Grand Autumn Rebalancing\u{2026}"))
        #expect(variants.contains("The Grand Autumn Rebalancing, Quality of Life\u{2026}"))
        #expect(variants.contains("The Grand Autumn Rebalancing, Quality of Life: Stability\u{2026}"))
        #expect(variants.contains("The Grand Autumn Rebalancing, Quality of Life: Stability; Update\u{2026}"))
        for v in variants.dropFirst() {
            #expect(v.hasSuffix("\u{2026}") && !",;:.".contains(v.dropLast().last!), "\(v)")
        }
        #expect(variants.first == title, "the whole text is never trimmed")
    }

    /// SwiftUI calls PickVariant (a Layout) from its async renderer thread, off the main actor. The helpers are nonisolated and
    /// pure; this calls them from a detached task, where a main-actor-inferred helper trapped (36d340c-crash-WholeWordText.ips).
    @Test func helpersRunOffTheMainActor() async {
        let title = "E3 2018 Open Beta Trailer for the Crew Two"
        let (all, fit, words) = await Task.detached {
            let widths: [Int: CGFloat] = Dictionary(uniqueKeysWithValues: WholeWordText.words(of: title).indices.map { ($0, CGFloat(30)) })
            return (WholeWordText.variants(of: title), WholeWordText.fittingVariants(of: title, wordWidths: widths, available: 100), WholeWordText.words(of: title))
        }.value
        #expect(all.first == title)
        #expect(fit == all)
        #expect(words.count == 9)
    }
}
