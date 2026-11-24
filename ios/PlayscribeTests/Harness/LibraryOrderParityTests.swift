import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// B-12 (docs/ux-acceptance.md): one Library order in every pose, with one accessibility exception (Nadia, 24 Nov; #610 for
/// Tabletop, #635 for Closed): at AX sizes in Closed and Tabletop the filter chips follow the tiles. This holds the rule strictly.
/// In every pose and at every size the same blocks are present. At AX sizes each pose keeps its standard-size order with the chips
/// taken out, so only the chips block may move. The chips follow the tiles exactly where the exception applies, and nowhere else
/// do they move relative to the tiles.
///
/// Blocks are the frames the Library reports by name: the chips, the tiles, the deck and the cards after the games. Order is by
/// top edge. A pose can lay its blocks out differently from another pose (Book's pages, the deck after the tiles in Closed
/// landscape); what this test forbids is a block that appears, vanishes or moves when only the text size changes.
@MainActor
struct LibraryOrderParityTests {
    static let blocks = ["libraryChips", "libraryGames", "latestDeck", "libraryCards"]
    static let poses = ["closed", "closedLandscape", "open", "openPortrait", "book", "tabletop"]

    private func order(_ r: Rendered) -> [String] {
        Self.blocks.compactMap { name in r.named[name].map { (name, $0) } }
            .sorted { ($0.1.minY, $0.0) < ($1.1.minY, $1.0) }
            .map(\.0)
    }

    @Test(arguments: poses, [UIContentSizeCategory.accessibilityExtraLarge, .accessibilityExtraExtraExtraLarge])
    func onlyTheChipsMoveAtAccessibilitySizes(_ id: String, _ size: UIContentSizeCategory) async throws {
        let p = HarnessPose.named(id)
        let std = try #require(await FoldHost.render(p, type: .large), "\(id): a window scene to host in")
        let standard = order(std)
        FoldHost.dispose(std)
        let ax = try #require(await FoldHost.render(p, type: size), "\(id): a window scene to host in")
        let large = order(ax)
        FoldHost.dispose(ax)
        print("harness order: \(id) std \(standard) \(size.rawValue) \(large)")

        // The same blocks at both sizes: nothing appears or vanishes with the text size, the chips included.
        #expect(Set(standard) == Set(large), "\(id) B-12: blocks differ by text size: std \(standard), \(size.rawValue) \(large)")
        #expect(standard.contains("libraryChips") && standard.contains("libraryGames"), "\(id): the demo Library shows chips and tiles (\(standard))")
        // Everything but the chips keeps its order.
        #expect(standard.filter { $0 != "libraryChips" } == large.filter { $0 != "libraryChips" },
                "\(id) B-12: a block other than the chips moved at \(size.rawValue): std \(standard), AX \(large)")

        guard let chipsStd = standard.firstIndex(of: "libraryChips"), let gamesStd = standard.firstIndex(of: "libraryGames"),
              let chipsAX = large.firstIndex(of: "libraryChips"), let gamesAX = large.firstIndex(of: "libraryGames") else { return }
        let exception = LibraryShelf.chipsFollowTiles(pose: p.expected, accessibilitySize: true)
        if exception {
            // At standard size the chips lead the tiles (one order); at AX they follow, directly after the tiles.
            #expect(chipsStd < gamesStd, "\(id): at standard size the chips lead the tiles (\(standard))")
            #expect(chipsAX == gamesAX + 1, "\(id) B-12: at \(size.rawValue) the chips follow the tiles directly (\(large))")
        } else {
            #expect(standard == large, "\(id) B-12: no exception here, so the order is the same at \(size.rawValue): std \(standard), AX \(large)")
        }
    }

    @Test func theExceptionIsClosedAndTabletopAtAccessibilitySizesOnly() {
        for pose in [Pose.closed, .flat, .book, .tabletop] {
            #expect(!LibraryShelf.chipsFollowTiles(pose: pose, accessibilitySize: false), "\(pose): standard sizes keep one order")
        }
        #expect(LibraryShelf.chipsFollowTiles(pose: .closed, accessibilitySize: true))
        #expect(LibraryShelf.chipsFollowTiles(pose: .tabletop, accessibilitySize: true))
        #expect(!LibraryShelf.chipsFollowTiles(pose: .flat, accessibilitySize: true))
        #expect(!LibraryShelf.chipsFollowTiles(pose: .book, accessibilitySize: true))
    }
}
