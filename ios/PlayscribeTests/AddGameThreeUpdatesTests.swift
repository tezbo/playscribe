import Foundation
import Testing
@testable import Playscribe

/// qa-route-add-game-3-updates: adding a game with three PS5 updates from the last 72 hours leaves only the newest unread
/// (#480, R-6, N-3), so its tile shows one "New update" and the badge reads 1.
@MainActor
struct AddGameThreeUpdatesTests {
    private func model() -> AppModel {
        AppModel(storeURL: URL.temporaryDirectory.appending(path: "add3-\(UUID().uuidString).json"))
    }

    @Test func addedGameKeepsOnlyItsNewestUpdateUnread() throws {
        let m = model()
        let id = try #require(m.resetToAddGameDemo())
        #expect(m.entry(id) != nil)
        let recent = m.releases(id).filter { $0.id.hasPrefix("qa-add3-") }
        #expect(recent.count == 3)
        #expect(m.unreadCount(id) == 1)
        #expect(m.releases(id).first { m.isUnread($0) }?.id == "qa-add3-\(id)-3")
        #expect(m.badgeCount == 1)
    }

    @Test func aNamedGameInTheLibraryIsAddedAfresh() throws {
        let m = model()
        m.resetDemo()
        let inLibrary = try #require(m.data.collection.first?.gameID)
        #expect(m.resetToAddGameDemo(gameID: inLibrary) == inLibrary)
        #expect(m.unreadCount(inLibrary) == 1)
        #expect(m.badgeCount == 1)
    }
}
