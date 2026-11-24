import SwiftUI
import Testing
@testable import Playscribe

/// Iris (#619): the Tabletop reader's plate never clips at the stage's top, and never drops a line of content.
struct ReaderPlateFitTests {
    /// 41e69f7b, tabletop-*-reader-ax5: the room above the fold was about 170 pt and the drawn plate about 230 pt, with its
    /// "Out on PS5 01.006.000" row cut at the top. A plate taller than the room steps down until it fits.
    @Test func tallPlateStepsDownUntilItFits() {
        let room: CGFloat = 170
        // Heights as each level draws them on that stage (title already on one line, so level 1 is no shorter).
        let drawn: [CGFloat] = [230, 230, 196, 150, 120]
        var level = 0
        for _ in 0..<10 {
            let next = ReaderPlateFit.next(level: level, plateHeight: drawn[level], room: room)
            if next == level { break }
            level = next
        }
        #expect(level == 3)
        #expect(drawn[level] <= room)
    }

    @Test func plateThatFitsStaysFull() {
        #expect(ReaderPlateFit.next(level: 0, plateHeight: 160, room: 170) == 0)
        #expect(ReaderPlateFit.next(level: 0, plateHeight: 170.4, room: 170) == 0)
    }

    @Test func neverPastTheLastLevelAndNoRoomMeansNoStep() {
        let last = ReaderPlateFit.levels.count - 1
        #expect(ReaderPlateFit.next(level: last, plateHeight: 900, room: 170) == last)
        #expect(ReaderPlateFit.next(level: 0, plateHeight: 900, room: 0) == 0)
    }

    /// Same content in every pose: every level keeps the title and the overview's headline, each on at least one line, the title
    /// is cut before the headline, and the type cap only ever tightens.
    @Test func levelsKeepEveryLineAndCutTheTitleFirst() {
        let levels = ReaderPlateFit.levels
        #expect(levels.first == .init(titleLines: nil, subtitleLines: 2, typeCap: .accessibility5))
        for l in levels { #expect((l.titleLines ?? 1) >= 1); #expect(l.subtitleLines >= 1) }
        let firstTitleCut = levels.firstIndex { $0.titleLines == 1 }!
        let firstHeadlineCut = levels.firstIndex { $0.subtitleLines == 1 }!
        #expect(firstTitleCut < firstHeadlineCut)
        for (a, b) in zip(levels, levels.dropFirst()) { #expect(b.typeCap <= a.typeCap) }
    }
}
