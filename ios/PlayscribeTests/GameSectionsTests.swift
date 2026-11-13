import Foundation
import Testing
@testable import Playscribe

/// R-7 (0.5.6 redesign, Card C): five sections in a fixed order, World and Companion merged, empty sections hidden.
@MainActor
struct GameSectionsTests {
    typealias C = GameSections.Content

    @Test func fullGameShowsAllFiveInOrder() {
        let c = C(worldEntries: 3, tipEntries: 2, newsCount: 4, galleryItems: 2)
        #expect(GameSections.visible(c) == [.updates, .news, .companion, .gallery, .mybook])
        #expect(!GameSections.visible(c).contains(.world))
    }

    @Test func emptySectionsHideButWhatsNewAndMyBookStay() {
        let c = C(worldEntries: 0, tipEntries: 0, newsCount: 0, galleryItems: 0)
        #expect(GameSections.visible(c) == [.updates, .mybook])
    }

    @Test func newsShowsWhileLoadingOrFailedAndHidesOnlyWhenLoadedEmpty() {
        #expect(GameSections.visible(C(newsCount: nil)).contains(.news))
        #expect(!GameSections.visible(C(newsCount: 0)).contains(.news))
        #expect(GameSections.visible(C(newsCount: 1)).contains(.news))
    }

    @Test func newsOnScreenNeverVanishesUnderTheReader() {
        #expect(GameSections.visible(C(newsCount: 0), current: .news).contains(.news))
        #expect(!GameSections.visible(C(newsCount: 0), current: .updates).contains(.news))
    }

    @Test func eitherKindOfEntryShowsCompanion() {
        #expect(GameSections.visible(C(worldEntries: 1)).contains(.companion))
        #expect(GameSections.visible(C(tipEntries: 1)).contains(.companion))
    }

    @Test func storedSectionResolves() {
        let all = GameSections.visible(C(worldEntries: 1, tipEntries: 1, newsCount: 1, galleryItems: 1))
        #expect(GameSections.resolve(.world, in: all) == .companion)
        #expect(GameSections.resolve(.gallery, in: all) == .gallery)
        let bare = GameSections.visible(C(newsCount: 0))
        #expect(GameSections.resolve(.gallery, in: bare) == .updates)
        #expect(GameSections.resolve(.world, in: bare) == .updates)
    }

    @Test func filterOnlyWithBothKinds() {
        #expect(GameSections.companionFilters(C(worldEntries: 2, tipEntries: 1)) == [.world, .companion])
        #expect(GameSections.companionFilters(C(worldEntries: 2)).isEmpty)
        #expect(GameSections.companionFilters(C(tipEntries: 2)).isEmpty)
        #expect(GameSections.companionKind(nil, C(worldEntries: 2, tipEntries: 1)) == .world)
        #expect(GameSections.companionKind(.companion, C(worldEntries: 2, tipEntries: 1)) == .companion)
        #expect(GameSections.companionKind(.companion, C(worldEntries: 2)) == nil)
        #expect(GameSections.filterTitle(.world) == "World")
        #expect(GameSections.filterTitle(.companion) == "Tips")
    }

    // The model, on the bundled fixtures: Dawnwalker has World and Tips entries; KCD2 has none.

    private func model() -> AppModel { AppModel(storeURL: URL.temporaryDirectory.appending(path: "sections-\(UUID().uuidString).json")) }

    @Test func dawnwalkerHasCompanionWithTheFilter() {
        let m = model()
        #expect(m.chapters("dawnwalker").contains(.companion))
        #expect(m.companionKind("dawnwalker") == .world)
        m.setCompanionKind("dawnwalker", .companion)
        #expect(m.companionKind("dawnwalker") == .companion)
    }

    @Test func aGameWithoutEntriesHasNoCompanion() {
        let m = model()
        #expect(!m.chapters("kcd2").contains(.companion))
        m.openGame("kcd2", chapter: .companion)
        #expect(m.section("kcd2") == .updates)
    }

    @Test func openingAnEntryLandsOnCompanionAtItsKind() throws {
        let m = model()
        let tip = try #require(m.fixtures.book.first { $0.gameID == "dawnwalker" && $0.chapter == .companion })
        m.openGame("kcd2")
        m.openEntry(tip)
        #expect(m.nav.gameID == "dawnwalker")
        #expect(m.section("dawnwalker") == .companion)
        #expect(m.companionKind("dawnwalker") == .companion)
        #expect(m.nav.anchors[AppModel.bookKey("dawnwalker", .companion)] == "entry-\(tip.id)")
    }

    @Test func worldChapterOpensCompanion() {
        let m = model()
        m.openGame("dawnwalker", chapter: .world)
        #expect(m.nav.chapter == .companion)
    }
}
