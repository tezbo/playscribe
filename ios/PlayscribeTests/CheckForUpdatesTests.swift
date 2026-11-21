import Foundation
import Testing
@testable import Playscribe

/// More > Check for updates always ends in a toast that says what happened (Terry, 21 Nov).
@MainActor
struct CheckForUpdatesTests {
    @Test func resultLines() {
        let d = Date(timeIntervalSince1970: 1_763_700_000)
        #expect(AppModel.checkResult(.checked(d), newUpdates: 1) == "1 new update")
        #expect(AppModel.checkResult(.checked(d), newUpdates: 2) == "2 new updates")
        #expect(AppModel.checkResult(.checked(d), newUpdates: 0) == "Up to date. Checked \(AppModel.checkedStamp(d))")
        #expect(AppModel.checkResult(.failed(offline: true), newUpdates: 0) == "Couldn’t check. You’re offline")
        #expect(AppModel.checkResult(.failed(offline: false), newUpdates: 0) == "Couldn’t check. Try again later")
        #expect(AppModel.checkResult(.notChecked, newUpdates: 0) == "Couldn’t check. Try again later")
    }

    @Test func menuItemRunsTheCheck() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI/Actions.swift"), encoding: .utf8)
        #expect(src.contains("checkForUpdates(gameID)"))
    }
}
