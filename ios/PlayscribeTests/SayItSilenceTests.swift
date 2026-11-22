import Foundation
import Testing
@testable import Playscribe

/// Say it is tap to start and stops itself after a pause (Terry, 22 Nov: hold-to-talk was an odd choice).
@MainActor
struct SayItSilenceTests {
    /// Records each requested pause; a pause either finishes at once or waits until it is cancelled.
    final class Pauses: @unchecked Sendable {
        var asked: [Duration] = []
        var finish = true
        func sleep(_ d: Duration) async throws {
            asked.append(d)
            if finish { return }
            try await Task.sleep(for: .seconds(3600))
        }
    }

    @Test func waitsLongerBeforeTheFirstWord() async {
        let pauses = Pauses()
        var fired = 0
        let watch = SilenceWatch(sleep: { try await pauses.sleep($0) }, fire: { fired += 1 })
        watch.arm(heard: false)
        await settle { fired == 1 }
        watch.arm(heard: true)
        await settle { fired == 2 }
        #expect(pauses.asked == [SilenceWatch.beforeSpeech, SilenceWatch.afterSpeech])
        #expect(SilenceWatch.beforeSpeech > SilenceWatch.afterSpeech)
        #expect(SilenceWatch.afterSpeech <= .seconds(2), "a pause after speaking ends it quickly")
    }

    /// A new word restarts the timer: the earlier pause never stops listening.
    @Test func newWordReplacesThePendingPause() async {
        let pauses = Pauses()
        pauses.finish = false
        var fired = 0
        let watch = SilenceWatch(sleep: { try await pauses.sleep($0) }, fire: { fired += 1 })
        watch.arm(heard: false)
        await settle { pauses.asked.count == 1 }
        pauses.finish = true
        watch.arm(heard: true)
        await settle { fired == 1 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fired == 1, "the replaced pause was cancelled, not fired")
    }

    @Test func tapToStopCancelsThePause() async {
        let pauses = Pauses()
        pauses.finish = false
        var fired = 0
        let watch = SilenceWatch(sleep: { try await pauses.sleep($0) }, fire: { fired += 1 })
        watch.arm(heard: true)
        await settle { pauses.asked.count == 1 }
        watch.cancel()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fired == 0)
    }

    /// No hold gesture is left on the microphone.
    @Test func microphoneIsATapNotAHold() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI/SayItView.swift"), encoding: .utf8)
        #expect(!src.contains("onLongPressGesture"))
        #expect(!src.contains("Hold to talk"))
        #expect(src.contains("capture.toggle()"))
    }

    private func settle(_ done: () -> Bool) async {
        for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(5)) }
    }
}
