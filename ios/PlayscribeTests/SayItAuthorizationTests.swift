import Foundation
import Speech
import Testing
@testable import Playscribe

/// #570: Say it crashed in build 16 when Speech answered the permission request on its own queue.
@MainActor
struct SayItAuthorizationTests {
    /// Asked from the main actor, answered on a background queue, as Speech does on a device.
    @Test func authorizationAnsweredOffMainDoesNotTrap() async {
        let granted = await SpeechCapture.speechAuthorized { handler in
            nonisolated(unsafe) let h = handler; DispatchQueue.global().async { h(.authorized) }
        }
        #expect(granted)
        let denied = await SpeechCapture.speechAuthorized { handler in
            nonisolated(unsafe) let h = handler; DispatchQueue.global().async { h(.denied) }
        }
        #expect(!denied)
    }

    /// The handler is never written inline inside the main-actor class again.
    @Test func noInlineAuthorizationHandler() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI/SayItView.swift"), encoding: .utf8)
        #expect(!src.contains("SFSpeechRecognizer.requestAuthorization {"))
        #expect(src.contains("nonisolated static func speechAuthorized("), "the request is made off the main actor")
    }
}
