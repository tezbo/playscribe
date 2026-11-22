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

    @Test func twoCardsOnScreenDrawOneCapsule() {
        // Iris: the lit leaves join into one amber capsule from the first to the last card on screen.
        let r = PageEdge.capsule(lit: [1, 2], window: [0, 1, 2, 3])
        #expect(r == CGRect(x: 44 + 22 - 1.5, y: 13, width: 44 + 3, height: 18))
    }

    @Test func oneCardOnScreenKeepsTheSingleMark() {
        let r = PageEdge.capsule(lit: [2], window: [0, 1, 2, 3])
        #expect(r == CGRect(x: 88 + 22 - 1.5, y: 13, width: 3, height: 18))
    }

    @Test func capsuleFollowsTheSlidingWindow() {
        // A long deck shows five leaves; the capsule is placed by slot in the window, not by card index.
        #expect(PageEdge.capsule(lit: [6, 7], window: [4, 5, 6, 7, 8])?.minX == 2 * 44 + 22 - 1.5)
        #expect(PageEdge.capsule(lit: [], window: [0, 1]) == nil)
    }

    @Test(arguments: [835, 834, 836.5, 700] as [CGFloat])
    func twoAcrossFillThePagerExactly(pager: CGFloat) {
        // J-8: at the last page both cards sit flush on the margins; two cards and the 12 pt gap are the pager wide.
        let w = LatestUpdatesDeck.cardWidth(in: pager, perScreen: 2)
        #expect(abs(2 * w + 12 - pager) < 0.001)
    }
}
