import Foundation
import Testing
@testable import Playscribe

/// Iris and Quinn on #512 (Open landscape std): a fast flick skipped a card, and with two cards across the fifth leaf never lit.
/// The pager moves one card per flick (`.viewAligned(limitBehavior: .alwaysByOne)`), every card on screen lights its leaf,
/// and a VoiceOver step on a leaf moves exactly one card. The swipes themselves are `LatestUpdatesDeckTests` (UI).
struct DeckPagingTests {
    private let cards = (1...5).map { i in
        DeckCard(game: CatalogGame(id: "g\(i)", name: "Game \(i)", platforms: [.ps5], coverage: .none), release: nil, unread: false, date: nil)
    }

    @Test func twoAcrossLightsBothAndTheLastLeafAtTheEnd() {
        // Lead on card 4 is as far as the pager goes with two across: cards 4 and 5 show, both lit.
        #expect(PageEdge.lit(cards: cards, current: cards[3].id, visible: 2) == [3, 4])
        // A tap on leaf 5 asks for card 5 as lead; the pager still shows 4 and 5, and 5 is lit.
        #expect(PageEdge.lit(cards: cards, current: cards[4].id, visible: 2).contains(4))
        #expect(PageEdge.lit(cards: cards, current: cards[0].id, visible: 2) == [0, 1])
        #expect(PageEdge.lit(cards: cards, current: cards[2].id, visible: 1) == [2])
    }

    @Test func aStepMovesExactlyOneCard() {
        #expect(PageEdge.step(cards: cards, current: cards[0].id, visible: 1, by: 1) == cards[1].id)
        #expect(PageEdge.step(cards: cards, current: cards[2].id, visible: 1, by: -1) == cards[1].id)
        #expect(PageEdge.step(cards: cards, current: cards[0].id, visible: 1, by: -1) == nil, "no step before the first card")
    }

    @Test func everyCardAndLeafIsReachableByStepping() {
        for visible in [1, 2] {
            var current = cards[0].id, seen: Set<Int> = PageEdge.lit(cards: cards, current: current, visible: visible), steps = 0
            while let next = PageEdge.step(cards: cards, current: current, visible: visible, by: 1) {
                let before = cards.firstIndex { $0.id == current }!, after = cards.firstIndex { $0.id == next }!
                #expect(after == before + 1, "one card per step (\(visible) across)")
                current = next
                seen.formUnion(PageEdge.lit(cards: cards, current: current, visible: visible))
                steps += 1
            }
            #expect(seen == Set(0..<cards.count), "\(visible) across: every leaf lights on the way, the last one included")
            #expect(steps == cards.count - visible)
        }
    }

    /// The pager's limit: one view per flick, however fast. On the head before this fix it was plain `.viewAligned`.
    @Test func aFlickMovesOneCard() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI/LatestUpdatesDeck.swift"), encoding: .utf8)
        #expect(src.contains(".scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))"))
        #expect(!src.contains(".scrollTargetBehavior(.viewAligned)\n"))
    }

    @Test func twoCardsOnScreenDrawOnePillOverTheirDots() {
        // Iris (beta 4 redesign): 6 pt dots 10 pt apart; two lit cards are one pill, exactly 22 pt wide, over dots 2 and 3.
        let r = PageEdge.pill(lit: [1, 2], window: [0, 1, 2, 3])
        #expect(r == CGRect(x: 16, y: 0, width: 22, height: 6))
    }

    @Test func oneCardOnScreenIsADot() {
        let r = PageEdge.pill(lit: [2], window: [0, 1, 2, 3])
        #expect(r == CGRect(x: 32, y: 0, width: 6, height: 6))
    }

    @Test func pillFollowsTheWindow() {
        // A long deck shows five dots; the pill is placed by position in the window, not by card index.
        #expect(PageEdge.pill(lit: [6, 7], window: [4, 5, 6, 7, 8])?.minX == 32)
        #expect(PageEdge.pill(lit: [], window: [0, 1]) == nil)
    }

    /// Iris on #616: no indicator when every card is on screen (one page), in any pose; light unlit dots are #A39B97, 2.5:1 on cream.
    @Test func onePageHasNoIndicatorAndLightDotsMeasure() {
        #expect(PageEdge.hidden(count: 1, visible: 1))
        #expect(PageEdge.hidden(count: 2, visible: 2))
        #expect(!PageEdge.hidden(count: 2, visible: 1))
        #expect(!PageEdge.hidden(count: 3, visible: 2))
        let r = Contrast.ratio(PageEdge.unlitLight, PlayscribeRole.resolved(PlayscribeRole.bgSpec, light: true))
        #expect(r >= 2.4 && r < 3, "light unlit dot \(r):1 on bg")
    }

    @Test func indicatorIsOneSpokenElement() {
        #expect(PageEdge.spoken(lit: [1, 2], count: 5) == "Updates 2 and 3 of 5")
        #expect(PageEdge.spoken(lit: [0], count: 5) == "Update 1 of 5")
    }

    /// Fixed sizes: the indicator never scales with Dynamic Type, and never animates (Iris).
    @Test func indicatorHasFixedSizesAndNoAnimation() throws {
        #expect(PageEdge.dot == 6 && PageEdge.gap == 10)
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI/LatestUpdatesDeck.swift"), encoding: .utf8)
        let body = try #require(src.range(of: "struct PageEdge: View {")).upperBound
        let rest = src[body...]
        let end = try #require(rest.range(of: "\n}\n")).lowerBound
        let pageEdge = rest[..<end]
        #expect(!pageEdge.contains("@ScaledMetric"))
        #expect(pageEdge.contains(".transaction { $0.animation = nil }"))
    }

    private func target(_ i: Int, _ visible: Int) -> [Int] {
        let t = LatestUpdatesDeck.tapTarget(index: i, count: 5, visible: visible)
        return [t.index, t.trailing ? 1 : 0]
    }

    @Test func aLeafThatCannotLeadScrollsTheLastCardToTheTrailingEdge() {
        // J-8 (Mac de571b0a): tapping leaf 5 asked the pager to lead with card 5, past the scroll end; it overshot 16 pt.
        // Open, two across: leaves 4 and 5 both land on the end page; Closed, one across: only leaf 5 does.
        #expect(target(4, 2) == [4, 1])
        #expect(target(3, 2) == [4, 1])
        #expect(target(2, 2) == [2, 0])
        #expect(target(4, 1) == [4, 1])
        #expect(target(3, 1) == [3, 0])
    }

    @Test func atTheEndThePageCountsFromTheLastWholeScreen() {
        // Open at its end shows cards 4 and 5: "page 4 of 5", leaves 4 and 5 lit. Closed at its end: card 5.
        #expect(LatestUpdatesDeck.shownIndex(current: 4, count: 5, visible: 2, atEnd: true) == 3)
        #expect(LatestUpdatesDeck.shownIndex(current: 3, count: 5, visible: 1, atEnd: true) == 4)
        #expect(LatestUpdatesDeck.shownIndex(current: 1, count: 5, visible: 2, atEnd: false) == 1)
        #expect(LatestUpdatesDeck.shownIndex(current: 0, count: 1, visible: 2, atEnd: true) == 0)
    }
}
