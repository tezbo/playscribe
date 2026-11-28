import Foundation
import Testing
@testable import Playscribe

/// bug-079 (Terry, beta 6: tapping "PS Plus games leaving soon" opened the app wherever it was): every notification the app
/// can send maps to its own screen, from its payload or, for a local alert an older build scheduled, its identifier.
struct NotificationRouteTests {
    @Test("A PS5 update (pushed, simulated or day-one) opens that update, not the newest")
    func releaseOpensThatUpdate() {
        #expect(NotificationRoute(identifier: "x", userInfo: ["gameId": "dawnwalker", "releaseId": "dawnwalker@1.1"])
                == .release(gameID: "dawnwalker", releaseID: "dawnwalker@1.1"))
    }

    @Test("PS Plus leaving soon opens the PS Plus card, by kind or by an older build's identifier")
    func plusLeavingOpensTheCard() {
        #expect(NotificationRoute(identifier: "plus-leaving-2026-11", userInfo: ["kind": "plus-leaving"]) == .plusCard)
        #expect(NotificationRoute(identifier: "plus-leaving-2026-11", userInfo: [:]) == .plusCard)
    }

    @Test("A game's own alerts (release day, date move, issue fixed) open the game's page")
    func gameAlertsOpenTheGame() {
        for kind in ["release-day", "date-move", "issue-fixed"] {
            #expect(NotificationRoute(identifier: "\(kind)-1", userInfo: ["kind": kind, "gameId": "dawnwalker"]) == .game("dawnwalker"))
        }
        // A release-day alert an older build scheduled carries only its identifier.
        #expect(NotificationRoute(identifier: "release-day-dawnwalker", userInfo: [:]) == .game("dawnwalker"))
    }

    @Test("Anything with no screen of its own (team alerts, an empty payload) opens the Library top")
    func restOpensLibrary() {
        #expect(NotificationRoute(identifier: "team", userInfo: [:]) == .library)
        #expect(NotificationRoute(identifier: "release-day-", userInfo: [:]) == .library)
        #expect(NotificationRoute(identifier: "date-move-1:2", userInfo: ["gameId": ""]) == .library)
        #expect(NotificationRoute(identifier: "x", userInfo: ["gameId": "dawnwalker", "releaseId": ""]) == .game("dawnwalker"))
    }

    @Test("The bundled QA payloads map as the hosted run expects")
    func qaPayloadsMap() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "tools/qa")
        let want: [String: NotificationRoute] = [
            "release.apns": .release(gameID: "dawnwalker", releaseID: "dawnwalker@1.1"), "plus-leaving.apns": .plusCard,
            "release-day.apns": .game("dawnwalker"), "date-move.apns": .game("dawnwalker"), "issue-fixed.apns": .game("dawnwalker"),
            "team.apns": .library,
        ]
        for (file, route) in want {
            let data = try Data(contentsOf: dir.appending(path: file))
            let info = try #require(try JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any])
            #expect(NotificationRoute(identifier: "remote", userInfo: info) == route, "\(file)")
        }
    }
}
