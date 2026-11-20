import Testing
import WebKit
@testable import Playscribe

/// R-11, TT-4: a video plays inside our layout in every pose and never hands off to the iOS fullscreen player.
/// Terry's Duo, 20 Nov (IMG_0170): pressing play in Tabletop opened the system fullscreen player, so neither the transport nor
/// the reflection could show. The configuration already allowed inline playback; the hand-off came from a fullscreen request
/// inside YouTube's embed frame, which WebKit fulfils with the native player. The simulator played inline, so every earlier
/// reflection test passed.
@MainActor
struct InlineVideoTests {
    @Test("The player's web view plays inline and refuses every fullscreen request, in every frame (R-11)")
    func videoStaysInline() {
        let controller = YouTubeController(videoID: "abc", autoplay: false)
        let config = controller.webView.configuration
        #expect(config.allowsInlineMediaPlayback)
        #expect(!config.preferences.isElementFullscreenEnabled)
        // YouTube's player lives in a cross-origin iframe, so the guard must be injected into every frame, before its scripts run.
        let guardScript = config.userContentController.userScripts.first { $0.source.contains("webkitEnterFullscreen") }
        #expect(guardScript != nil, "a script blocks the video element's fullscreen entry")
        #expect(guardScript?.isForMainFrameOnly == false)
        #expect(guardScript?.injectionTime == .atDocumentStart)
        #expect(guardScript?.source.contains("webkitbeginfullscreen") == true, "and returns to inline if fullscreen begins anyway")
    }

    @Test("The embed asks for inline playback and drops YouTube's fullscreen button (R-11)")
    func embedParameters() {
        let html = YouTubeController.html("abc", captions: false)
        #expect(html.contains("playsinline:1"))
        #expect(html.contains("fs:0"))
    }
}

@MainActor
struct VideoControlsTests {
    @Test("Tabletop drops YouTube's own controls; other poses keep them; Play waits for the player (TT-4, VB-3; Iris, Quinn on #552)")
    func controlsFollowPose() {
        let html = YouTubeController.html("abc", captions: false)
        #expect(html.contains("controls:controls"), "controls are chosen per build, not fixed")
        #expect(html.contains("function setControls"))
        let controller = YouTubeController(videoID: "abc", autoplay: false)
        #expect(controller.nativeControls)
        #expect(!controller.ready)
        controller.setNativeControls(false)
        #expect(!controller.nativeControls)
        #expect(!controller.ready, "the rebuilt player is not ready until it says so")
    }
}
