import Foundation
import Testing
@testable import Playscribe

/// More > Check for updates always ends in a toast that says what happened (Terry, 21 Nov).
@MainActor
struct CheckForUpdatesTests {
    @Test func resultLines() {
        let d = Date(timeIntervalSince1970: 1_763_700_000)
        let now = d.addingTimeInterval(9_780)  // feed built 4:32, checked 7:15: the toast says 7:15
        #expect(AppModel.checkResult(.checked(d), newUpdates: 1, at: now) == "1 new update")
        #expect(AppModel.checkResult(.checked(d), newUpdates: 2, at: now) == "2 new updates")
        #expect(AppModel.checkResult(.checked(d), newUpdates: 0, at: now) == "No new updates. Checked \(AppModel.boundStamp(now))")
        #expect(!AppModel.boundStamp(now).contains(" "), "the day and time never split")
        #expect(AppModel.checkResult(.failed(offline: true), newUpdates: 0, at: now) == "Couldn’t check. You’re offline")
        #expect(AppModel.checkResult(.failed(offline: false), newUpdates: 0, at: now) == "Couldn’t check. Try again later")
        #expect(AppModel.checkResult(.notChecked, newUpdates: 0, at: now) == "Couldn’t check. Try again later")
    }

    @Test func menuItemRunsTheCheck() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI/Actions.swift"), encoding: .utf8)
        #expect(src.contains("checkForUpdates(gameID)"))
        let root = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI/RootView.swift"), encoding: .utf8)
        #expect(root.contains("Text(toast.text).font(PlayscribeFont.subheadline).lineLimit(4)"), "the toast wraps at AX5, never truncates")
        #expect(root.contains("PlayscribeRole.chipFill, in: RoundedRectangle(cornerRadius: 22"), "wrapped text stays off the curved ends")
    }
}
