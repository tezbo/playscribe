import Foundation
import Testing
@testable import Playscribe

/// D-1 and N-6 as amended by the 0.5.6 redesign (Card D, s4.png): sections are siblings, an update is a pushed page,
/// a notification opens the update and Back goes to What's new then the Library, and Back from the game goes to where it
/// was opened from.
@MainActor
struct NavBackTests {
    private func model() -> AppModel {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "back-\(UUID().uuidString).json"))
        m.livePose = .closed
        return m
    }

    @Test func switchingSectionsAddsNoHistory() {
        let m = model()
        m.openGame("dawnwalker")
        m.nav.chapter = .news
        m.nav.chapter = .gallery
        m.nav.chapter = .updates
        #expect(m.nav.detailReleaseID == nil)
        m.closeGame()
        #expect(m.nav.gameID == nil)
        #expect(m.nav.tab == .library)
    }

    @Test func backFromTheGameReturnsToTheTabItCameFrom() throws {
        let m = model()
        m.nav.tab = .updates
        let r = try #require(m.ps5Releases("kcd2").first)
        m.openGame("kcd2", chapter: .updates, releaseID: r.id)
        #expect(m.nav.tab == .library)
        #expect(m.backTitle == "Back to Updates")
        m.closeGame()
        #expect(m.nav.gameID == nil)
        #expect(m.nav.tab == .updates)
        #expect(m.nav.returnTab == nil)
    }

    @Test func fromTheLibraryBackIsTheLibrary() {
        let m = model()
        m.openGame("kcd2")
        #expect(m.backTitle == "Back to Library")
        m.closeGame()
        #expect(m.nav.tab == .library)
    }

    @Test func aGameAlreadyOpenAndReachedFromSearchStillGoesBackToSearch() {
        let m = model()
        m.openGame("kcd2")
        m.nav.tab = .search
        m.openGame("kcd2")
        m.closeGame()
        #expect(m.nav.tab == .search)
    }

    @Test func aPushedUpdateBacksToItsListThenTheLibrary() throws {
        let m = model()
        m.openGame("kcd2")
        let r = try #require(m.ps5Releases("kcd2").dropFirst().first ?? m.ps5Releases("kcd2").first)
        m.select("kcd2", releaseID: r.id)
        m.nav.detailReleaseID = r.id
        // Back from the update: the game, on its list.
        m.nav.detailReleaseID = nil
        #expect(m.nav.gameID == "kcd2")
        #expect(m.section("kcd2") == .updates)
        m.closeGame()
        #expect(m.nav.gameID == nil)
    }

    @Test func aNotificationOpensTheUpdatePageThenWhatsNewThenTheLibrary() throws {
        let m = model()
        m.nav.tab = .news
        let r = try #require(m.ps5Releases("kcd2").first)
        m.openRelease(gameID: "kcd2", releaseID: r.id)
        #expect(m.nav.tab == .library)
        #expect(m.nav.gameID == "kcd2")
        #expect(m.nav.detailReleaseID == r.id)
        #expect(m.isViewing("kcd2", r.id))
        // Back: What's new.
        m.nav.detailReleaseID = nil
        #expect(m.section("kcd2") == .updates)
        #expect(m.backTitle == "Back to Library")
        // Back: the Library, not the tab that was showing when the alert came in.
        m.closeGame()
        #expect(m.nav.tab == .library)
        #expect(m.nav.gameID == nil)
    }

    @Test func sideBySideANotificationShowsTheUpdateOnThePageWithoutAPush() throws {
        let m = model()
        m.livePose = .book
        let r = try #require(m.ps5Releases("kcd2").first)
        m.openRelease(gameID: "kcd2", releaseID: r.id)
        #expect(m.nav.detailReleaseID == nil)
        #expect(m.selectedRelease("kcd2")?.id == r.id)
    }

    @Test func anUpdatesRowPushesTheUpdateOverTheListInClosed() throws {
        let m = model()
        m.nav.tab = .updates
        let r = try #require(m.ps5Releases("kcd2").first)
        m.markRead(r.id, false)
        m.openFromUpdates(r)
        #expect(m.nav.tab == .updates)
        #expect(m.nav.updatesRelease == ReleaseRef(gameID: "kcd2", releaseID: r.id))
        #expect(m.nav.gameID == nil)
        #expect(!m.isUnread(r))
        #expect(m.isViewing("kcd2", r.id))
        // Back: the list, in one step.
        m.nav.updatesRelease = nil
        #expect(m.nav.tab == .updates)
    }

    @Test func sideBySideAnUpdatesRowOpensTheGameWithTheUpdate() throws {
        let m = model()
        m.livePose = .book
        m.nav.tab = .updates
        let r = try #require(m.ps5Releases("kcd2").first)
        m.openFromUpdates(r)
        #expect(m.nav.updatesRelease == nil)
        #expect(m.nav.gameID == "kcd2")
        #expect(m.selectedRelease("kcd2")?.id == r.id)
        #expect(m.backTitle == "Back to Updates")
    }
}
