import AVFoundation
import SwiftUI
import WebKit

/// Plays a release's official video. YouTube's terms require its own embedded player, so the video
/// runs in a WKWebView with the IFrame Player API; Playscribe draws its own controls (R-11).
/// One controller and one web view are kept for the whole presentation, so playback continues
/// across pose changes (P-2): the view is moved, not rebuilt.
@Observable
final class YouTubeController: NSObject, WKScriptMessageHandler {
    let webView: WKWebView
    var isPlaying = false
    var isMuted = false
    var duration: Double = 0
    var current: Double = 0
    var failed = false
    /// The IFrame API's error code: 101 and 150 mean the owner blocks playing it in other apps (R-12).
    var errorCode: Int?
    var ready = false
    /// True once playback has begun at least once.
    var started = false
    /// True once the person has pressed Play (or autoplay asked for it). Until then the Tabletop stage shows our own art and no
    /// player at all; from then on YouTube's player is shown unobscured, with its own branding (YouTube API terms).
    var playRequested = false
    /// True once the player reports buffering or playing after Play, so a slow load never shows YouTube's loading screen.
    var playerShown = false
    /// Fullscreen requests the inline guard refused (R-11), counted for QA.
    var fullscreenRefused = 0
    /// When playback last paused, to tell a pause caused by the guard's refusal from the person's own.
    private var pausedAt: Date?

    /// Settings key for "Autoplay videos". Off by default (R-11, G-9).
    static let autoplayKey = "autoplayVideos"
    /// True when videos should start on their own: the setting is on and Reduce Motion is off (G-9).
    static var autoplayEnabled: Bool {
        UserDefaults.standard.bool(forKey: autoplayKey) && !UIAccessibility.isReduceMotionEnabled
    }

    /// `nativeControls`: YouTube's own controls from the first build (false when opened in Tabletop, TT-4). The page is not loaded
    /// yet when the view first learns its pose, so the starting value goes into the page itself (Iris on #552).
    init(videoID: String, autoplay: Bool = YouTubeController.autoplayEnabled, nativeControls: Bool = true) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // D-11: the trailer keeps playing in Picture in Picture when the person leaves the app.
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // R-11 (Terry's Duo, 20 Nov): Play in Tabletop opened the iOS fullscreen player, so our layout, transport and reflection
        // were gone. Inline playback was already allowed; the hand-off came from a fullscreen request inside YouTube's embed,
        // which WebKit fulfils with the native player. Element fullscreen stays off, and the guard below refuses every route
        // into fullscreen in every frame, including YouTube's cross-origin one.
        config.preferences.isElementFullscreenEnabled = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: Self.inlineGuard, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController = content
        webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        // The player fills the frame we give it. By default the web view's scroll view insets its content by any safe area
        // the frame overlaps, which shrank the full-screen picture (cloud run 45743580991: Closed landscape drew about
        // 443 x 332 inside a 672 x 378 frame, offset by the 84 pt leading inset; Open flat stopped 84 pt short of the edge).
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        super.init()
        content.add(self, name: "player")
        playRequested = autoplay
        self.nativeControls = nativeControls
        webView.loadHTMLString(Self.html(videoID, captions: captionsOn, autoplay: autoplay, controls: nativeControls), baseURL: URL(string: "https://playscribe.app"))
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any] else { return }
            let event = body["event"] as? String
            let state = body["state"] as? Int
            let time = body["time"] as? Double
            let duration = body["duration"] as? Double
            switch event {
            case "ready":
                self.duration = duration ?? 0
                // A pose change before the page loaded could not reach it: re-apply, and stay not ready while it rebuilds.
                let want = self.nativeControls ? 1 : 0
                if let built = body["controls"] as? Int, built != want { self.run("setControls(\(want))") } else { self.ready = true }
            case "state":
                if self.isPlaying && state == 2 { self.pausedAt = Date() }
                self.isPlaying = state == 1
                if state == 1 { self.started = true }
                // 1 playing, 3 buffering: the player has the picture, so the stage can show it (Iris, 20 Nov).
                if state == 1 || state == 3 { self.playerShown = true }
            case "time": self.current = time ?? 0; if let duration, duration > 0 { self.duration = duration }
            case "error": self.failed = true; self.errorCode = body["code"] as? Int
            case "fullscreenRefused": self.refusedFullscreen()
            default: break
            }
        }
    }

    /// R-13 (Mac at 0dcfd411): turning the phone while a video played made WebKit try its own fullscreen; the guard returned the
    /// video to inline, and leaving WebKit's fullscreen pauses it, so playback stopped. When the video was playing as the guard
    /// refused (or paused within the moment before), it plays on.
    private func refusedFullscreen() {
        fullscreenRefused += 1
        let wasPlaying = isPlaying || (pausedAt.map { Date().timeIntervalSince($0) < 1.5 } ?? false)
        guard wasPlaying else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !self.isPlaying else { return }
            self.run("player.playVideo()")
        }
    }

    func playPause() {
        if !isPlaying { playRequested = true }
        run(isPlaying ? "player.pauseVideo()" : "player.playVideo()")
    }
    func seek(to t: Double) { current = t; run("player.seekTo(\(t), true)") }
    func toggleMute() { isMuted.toggle(); run(isMuted ? "player.mute()" : "player.unMute()") }
    func skip(_ seconds: Double) { seek(to: max(0, min(duration, current + seconds))) }
    /// D-13: captions on or off persists.
    var captionsOn = UserDefaults.standard.object(forKey: "captionsOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(captionsOn, forKey: "captionsOn") }
    }
    func toggleCaptions() {
        captionsOn.toggle()
        run(captionsOn ? "player.loadModule('captions')" : "player.unloadModule('captions')")
    }
    func stop() { run("player.stopVideo()") }
    /// YouTube's own controls outside Tabletop (VB-3); none in Tabletop, where our transport is the only one and the stage
    /// takes no touches (TT-4; Iris, 20 Nov: YouTube's bar on the stage looked tappable, did nothing and was mirrored).
    /// The title bar and logo stay either way.
    private(set) var nativeControls = true
    func setNativeControls(_ on: Bool) {
        guard on != nativeControls else { return }
        nativeControls = on
        ready = false   // the player is rebuilt; its onReady sets this again
        // Paused, the rebuilt player would show YouTube's thumbnail: our art returns until it buffers or plays (Iris on #552).
        if !isPlaying { playerShown = false }
        // bug-071 (cloud run 45716362816 at b6104b0): asking the live player for its time during the full-screen switch, while
        // the scene turned, rebuilt it at 3:33 of 3:34 with a black picture. The time and play state we already hold (updated
        // every 0.5 s) are passed in instead.
        run("setControls(\(on ? 1 : 0),\(current.isFinite ? current : 0),\(isPlaying || playRequested ? "true" : "false"))")
    }
    private func run(_ js: String) { webView.evaluateJavaScript(js) }

    /// Injected at document start into every frame. Video and element fullscreen calls do nothing, and if WebKit enters
    /// fullscreen anyway (a native gesture, a rotation) the video is returned to inline at once. Picture in Picture is untouched.
    static let inlineGuard = """
    (function(){
      function told(){try{window.webkit.messageHandlers.player.postMessage({event:'fullscreenRefused'})}catch(e){}}
      var V=window.HTMLVideoElement&&HTMLVideoElement.prototype, E=Element.prototype;
      ['webkitEnterFullscreen','webkitEnterFullScreen'].forEach(function(k){if(V&&k in V){V[k]=function(){told()}}});
      ['requestFullscreen','webkitRequestFullscreen','webkitRequestFullScreen'].forEach(function(k){
        if(k in E){E[k]=function(){told();return Promise.reject(new TypeError('inline only'))}}});
      document.addEventListener('webkitbeginfullscreen',function(e){told();try{e.target.webkitExitFullscreen()}catch(_){}},true);
      document.addEventListener('webkitpresentationmodechanged',function(e){var v=e.target;
        if(v&&v.webkitPresentationMode==='fullscreen'){told();try{v.webkitSetPresentationMode('inline')}catch(_){}}},true);
    })();
    """

    static func html(_ id: String, captions: Bool, autoplay: Bool = false, controls: Bool = true) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body><div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player, controls=\(controls ? 1 : 0);
        function post(m){window.webkit.messageHandlers.player.postMessage(m)}
        // Builds the player. Rebuilt in place (same web view, same position) when the pose switches between YouTube's own
        // controls (Closed, Book, Open) and ours (Tabletop), since the IFrame API cannot change controls on a live player.
        function build(start,play){
          player=new YT.Player('p',{videoId:'\(id)',host:'https://www.youtube-nocookie.com',
            playerVars:{playsinline:1,fs:0,controls:controls,start:Math.floor(start),cc_load_policy:\(captions ? 1 : 0),autoplay:play?1:0,rel:0,modestbranding:1,iv_load_policy:3,origin:'https://playscribe.app'},
            events:{onReady:function(){if(start>0){player.seekTo(start,true)}post({event:'ready',duration:player.getDuration(),controls:controls});if(play){player.playVideo()}},
                    onStateChange:function(e){post({event:'state',state:e.data})},
                    onError:function(e){post({event:'error',code:e.data})}}});
        }
        function setControls(c,t,play){
          if(c===controls){return}
          controls=c;
          if(!player||!player.getCurrentTime){return}
          if(typeof t!=='number'){t=player.getCurrentTime()}
          if(typeof play!=='boolean'){play=player.getPlayerState()===1}
          player.destroy();
          var d=document.createElement('div');d.id='p';document.body.appendChild(d);
          build(t,play);
        }
        function onYouTubeIframeAPIReady(){
          build(0,\(autoplay ? "true" : "false"));
          setInterval(function(){if(player&&player.getCurrentTime){post({event:'time',time:player.getCurrentTime(),duration:player.getDuration()})}},500);
        }
        </script></body></html>
        """
    }
}

struct WebSurface: UIViewRepresentable {
    var webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// The update video (VB-1..VB-3, TT-4). The YouTube player is the system player here: YouTube's
/// terms require its own embed, so outside Tabletop its own controls are the only controls.
/// Tabletop is the one custom transport: video on the standing half, every control on the flat
/// half. One controller and one web view live for the whole presentation, so playback carries
/// through pose changes (P-2).
struct PlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var gameID: String
    var releaseID: String
    @State private var controller: YouTubeController?
    /// R-13: our own full-bleed mode (Closed and Open). Never the iOS fullscreen player.
    @State private var fullScreen = false
    /// Room for a two-line caption under the video, growing with Dynamic Type.
    @ScaledMetric(relativeTo: .headline) private var captionRoom: CGFloat = 64
    var body: some View {
        NavigationStack {
            DuoReader { duo in
                let release = model.release(gameID, releaseID)
                Group {
                    if let release, let video = release.video, let controller {
                        if controller.failed {
                            // The navigation bar's Close is there outside Tabletop, so the screen adds its own only in Tabletop
                            // (Quinn, Mac at c072400: Open portrait showed Close twice).
                            VideoUnavailable(videoID: video.youtubeID, title: video.label, code: controller.errorCode, showsClose: duo.pose == .tabletop) { close() }
                        } else if fullScreen && FullBleedVideo.offered(in: duo.pose) {
                            FullBleedVideo(controller: controller, posterAsset: video.posterAsset, game: model.game(gameID),
                                           title: [video.label, model.game(gameID)?.name ?? ""].filter { !$0.isEmpty }.joined(separator: ", "),
                                           division: duo.division, occlusions: duo.occlusions) { fullScreen = false }
                        } else {
                            layout(duo: duo, release: release, video: video, controller: controller)
                        }
                    } else if release?.video != nil {
                        Color.black   // the controller is made on appear
                    } else {
                        ContentUnavailableView("Video unavailable", systemImage: "play.slash")
                    }
                }
                .background(.black)
                .overlay(alignment: .bottomLeading) { VideoTimeProbe(controller: controller) }
                .onChange(of: [duo.pose == .tabletop, controller != nil, fullScreen], initial: true) {
                    // bug-071: in full screen our band controls drive the player, so YouTube's are off (controls=0).
                    controller?.setNativeControls(duo.pose != .tabletop && !fullScreen)
                }
                // Tabletop has no full screen: folding into it ends it, and it doesn't come back on its own.
                .onChange(of: FullBleedVideo.offered(in: duo.pose)) { _, offered in if !offered { fullScreen = false } }
                .toolbarVisibility(duo.pose == .tabletop || fullScreen ? .hidden : .automatic, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: close) { Label("Close", systemImage: "xmark") }
                    }
                    if FullBleedVideo.offered(in: duo.pose), controller?.failed == false {
                        ToolbarItem(placement: .primaryAction) { FullBleedVideo.EnterButton { fullScreen = true } }
                    }
                }
            }
        }
        .onAppear {
            if controller == nil, let id = model.release(gameID, releaseID)?.video?.youtubeID {
                let c = YouTubeController(videoID: id, nativeControls: model.livePose != .tabletop)
                // QA (route `video-blocked/<game>/<release>[/<code>]`): show the R-12 state without a real blocked video.
                if let code = model.qaVideoError { c.failed = true; c.errorCode = code }
                controller = c
            }
        }
    }

    @ViewBuilder
    private func layout(duo: DuoContext, release: Release, video: ReleaseVideo, controller: YouTubeController) -> some View {
        // A web view has no intrinsic size, so a 16:9 box carries the size and the view fills it.
        // Before Play, our poster and our Play (VideoStartCover), never YouTube's start screen (Mac at c072400).
        let surface = Color.black.aspectRatio(16 / 9, contentMode: .fit)
            .overlay { WebSurface(webView: controller.webView) }
            .overlay { VideoStartCover(controller: controller, posterAsset: video.posterAsset, game: model.game(gameID)) }
        let gameName = model.game(gameID)?.name ?? ""
        switch duo.pose {
        case .tabletop:
            TabletopVideoStage(controller: controller, video: video, game: model.game(gameID), gameName: gameName, release: release, onClose: close)
        case .book:
            // VB-2: the video and its details on the left page; Watch along on the right.
            if let fold = duo.division {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        surface
                        VideoCaption(video: video, game: gameName)
                            .padding(.horizontal, 16).padding(.top, 12)
                        Spacer(minLength: 0)
                    }
                    .frame(width: fold.minX)
                    Color.clear.frame(width: fold.width)
                    WatchAlong(controller: controller, release: release) { close(); model.openGame(gameID, chapter: .updates, releaseID: releaseID) }
                        .frame(maxWidth: .infinity)
                }
                .overlay(alignment: .topLeading) { MirrorAudit(on: false) }
            }
        case .closed, .flat:
            // VB-3: full display, the player's own controls once playing. The player is 16:9 and as large as the area allows
            // after a two-line caption, centred, so in Closed landscape it no longer runs to the window's edge (Quinn, c072400).
            GeometryReader { geo in
                let h = max(0, min(geo.size.width * 9 / 16, geo.size.height - captionRoom))
                VStack(spacing: 0) {
                    surface.frame(width: h * 16 / 9, height: h).frame(maxWidth: .infinity)
                    VideoCaption(video: video, game: gameName).frame(maxWidth: h * 16 / 9).padding(.horizontal, 16).padding(.top, 12)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity, alignment: duo.pose == .closed && !duo.isLandscape ? .top : .center)
            }
            .overlay(alignment: .topLeading) { MirrorAudit(on: false) }
        }
    }

    private func close() {
        controller?.stop()
        dismiss()
    }
}

/// R-13 (Terry on build 16, 21 Nov: "no full screen option when playing videos"), bug-071 (Terry on beta 5: "aren't truly full
/// screen"): our own full-screen mode. The same web view moves into a black frame the size of the whole screen, safe area
/// ignored (playback carries on, P-2); the navigation bar, status bar and home indicator hide. The picture is 16:9 Fit, as large
/// as the screen allows, centred: Iris's spec on the bug-071 card. YouTube's Required Minimum Functionality says "You must not
/// display overlays, frames, or other visual elements in front of any part of a YouTube embedded player", so nothing of ours
/// is ever drawn over the picture (Nadia's policy_decision on the card): Fill (cropping) is dropped, and every control sits in
/// the black letterbox bands, which are kept at least `minBand` tall so a 44 pt target fits (Closed landscape's natural band is
/// 42 pt, so there the picture is 3 pt shorter than the screen allows). Offered in Closed and Open (both orientations: from
/// portrait it asks the scene for landscape, as YouTube and Netflix do, and Exit turns back) and in Book, where the picture runs
/// across the fold and a guard band over the division takes the taps there (CLAUDE.md: nothing tappable intersects a
/// division). Tabletop keeps its own player. The VoiceOver escape gesture also leaves. No mirror here: Tabletop only.
struct FullBleedVideo: View {
    var controller: YouTubeController
    var posterAsset: String?
    var game: CatalogGame?
    /// The top band's title, e.g. "Update 1.2 trailer, The Blood of Dawnwalker".
    var title: String = ""
    /// Book: the active fold, in DuoReader's (safe-area) coordinates.
    var division: CGRect? = nil
    /// Active occlusions (camera housing), in DuoReader's coordinates. The picture never runs under one.
    var occlusions: [CGRect] = []
    var onExit: () -> Void

    static func offered(in pose: Pose) -> Bool { pose != .tabletop }

    /// The least height of a letterbox band, so a 44 pt control fits in it (policy_decision 3).
    static let minBand: CGFloat = 44

    /// Fit: the 16:9 frame as large as `size` (the whole screen) allows, with at least `band` above and below it, and clear of
    /// every rect in `avoiding` (screen coordinates). An occlusion over the picture pushes back only the side it sits on (spec 1,
    /// "that side only"): either the nearest top or bottom edge, or the nearest leading or trailing edge, whichever leaves the
    /// larger picture. The picture is centred in what remains. The safe area is not taken off: the status bar and home indicator
    /// are hidden, and the camera housing is an occlusion, measured. Cloud run 45730726202: widening both bands for Closed
    /// landscape's 84 x 82 corner housing left 536 x 302; pushing only the top edge leaves 604 x 340.
    static func fit(in size: CGSize, band: CGFloat = minBand, avoiding occlusions: [CGRect] = []) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        struct Insets { var top, bottom, left, right: CGFloat }
        func frame(_ i: Insets) -> CGRect {
            let rw = max(0, size.width - i.left - i.right), rh = max(0, size.height - i.top - i.bottom)
            let w = min(rw, rh * 16 / 9), h = w * 9 / 16
            return CGRect(x: i.left + (rw - w) / 2, y: i.top + (rh - h) / 2, width: w, height: h)
        }
        var insets = Insets(top: band, bottom: band, left: 0, right: 0)
        for _ in 0..<(occlusions.count * 2) {
            let f = frame(insets)
            guard let o = occlusions.first(where: { f.intersects($0) }) else { break }
            var vertical = insets, horizontal = insets
            if o.midY < size.height / 2 { vertical.top = max(vertical.top, o.maxY) }
            else { vertical.bottom = max(vertical.bottom, size.height - o.minY) }
            if o.midX < size.width / 2 { horizontal.left = max(horizontal.left, o.maxX) }
            else { horizontal.right = max(horizontal.right, size.width - o.minX) }
            insets = frame(vertical).width >= frame(horizontal).width ? vertical : horizontal
        }
        return frame(insets)
    }

    /// True when the scene was turned to landscape on entry, so Exit turns it back.
    @State private var turned = false
    /// bug-073: taps on the picture, heard without taking them from the player, so any tap brings the band controls back.
    @State private var pictureTaps = 0
    @State private var tapRelay = TapRelay()

    var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + safe.leading + safe.trailing, height: geo.size.height + safe.top + safe.bottom)
            let toScreen = { (r: CGRect) in r.offsetBy(dx: safe.leading, dy: safe.top) }
            // The picture is never smaller than before bug-071 (644 x 362 in Closed landscape): it takes the spec's 672 x 378 and
            // lets the camera sit over its corner, as hardware rather than anything of ours (Iris). Clearing the measured housing would
            // leave 604 x 340. Our band controls keep clear of the housing (FullScreenBands.layout).
            let f = Self.fit(in: full)
            ZStack(alignment: .topLeading) {
                Color.black
                Color.black
                    // YouTube's own iframe buttons (rewind, channel, thumbnails) are off and cannot be tapped here, so VoiceOver
                    // gets one element for the picture instead (Iris, #655). Our band controls carry every action.
                    .overlay { WebSurface(webView: controller.webView).accessibilityHidden(true) }
                    // The picture as one VoiceOver element; it takes no touches (taps on the picture stay YouTube's).
                    .overlay {
                        Color.clear
                            .accessibilityElement()
                            .accessibilityLabel(title.isEmpty ? "Video" : "Video, \(title)")
                            .accessibilityAddTraits(.isImage)
                            .accessibilityIdentifier("videoFullScreenPicture")
                    }
                    // Before playback only: our poster stands in for YouTube's start screen until Play.
                    .overlay { VideoStartCover(controller: controller, posterAsset: posterAsset, game: game) }
                    .frame(width: f.width, height: f.height)
                    .offset(x: f.minX, y: f.minY)
                if let division {
                    // Not visual: clear, so the picture shows across the fold, but it takes every tap there so nothing on the
                    // division is tappable (Nadia's take on the card).
                    let d = toScreen(division)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .frame(width: d.width, height: d.height)
                        .offset(x: d.minX, y: d.minY)
                        .accessibilityHidden(true)
                }
                FullScreenBands(controller: controller, title: title, pictureTaps: pictureTaps, picture: f, screen: full, safe: safe,
                                division: division.map(toScreen), housings: occlusions.map(toScreen), onExit: leave)
                #if INTERNAL
                // QA: what the frame math saw, for the cloud fullscreen scenario (the picture measured 522 x 294 in Closed
                // landscape at dd0f09d where 672 x 378 was expected).
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("qaFullScreen")
                    .accessibilityValue("occ=\(occlusions.map(toScreen).map { "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width))x\(Int($0.height))" }.joined(separator: ";")) pic=\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width))x\(Int(f.height)) safe=\(Int(safe.top)),\(Int(safe.leading)),\(Int(safe.bottom)),\(Int(safe.trailing)) full=\(Int(full.width))x\(Int(full.height))")
                    .offset(x: 2, y: 2)
                #endif
            }
            .frame(width: full.width, height: full.height)
            .offset(x: -safe.leading, y: -safe.top)
        }
        .accessibilityAction(.escape, leave)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .overlay(alignment: .topLeading) { MirrorAudit(on: false) }
        .onDisappear { tapRelay.detach(); turnBack() }
        .onAppear {
            tapRelay.attach(to: controller.webView) { pictureTaps += 1 }
            if division == nil, VideoOrientation.isPortrait {
                turned = true
                // Turn only once the player has rebuilt with our controls (at most 3 s), so the rebuild and WebKit's response to
                // the turn never overlap (cloud run 45716362816).
                Task { @MainActor in
                    for _ in 0..<30 where !controller.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    VideoOrientation.request(.landscape)
                }
            }
        }
    }

    private func leave() {
        turnBack()
        onExit()
    }

    /// Full screen can also end without Exit (folding to Tabletop, closing the video): the scene still goes back to portrait.
    private func turnBack() {
        guard turned else { return }
        turned = false
        VideoOrientation.request(.portrait)
    }

    /// The navigation bar button that enters full screen.
    struct EnterButton: View {
        var action: () -> Void
        var body: some View {
            Button(action: action) { Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                .accessibilityIdentifier("videoFullScreen")
        }
    }
}

/// QA only (internal builds launched with `-qaVideoTime YES`): an invisible element, `qaVideoTime`, whose value is the playback time
/// in seconds, so a UI test can check that turning or folding keeps the time (R-13, P-2). Absent otherwise, so VoiceOver never meets it.
struct VideoTimeProbe: View {
    var controller: YouTubeController?
    var body: some View {
        #if INTERNAL
        if UserDefaults.standard.bool(forKey: "qaVideoTime"), let controller {
            VStack(spacing: 0) {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("qaVideoTime")
                    .accessibilityValue(String(format: "%.1f", controller.current))
                // Whether it plays, and how many fullscreen attempts the inline guard refused (R-11, R-13).
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("qaVideoState")
                    .accessibilityValue("playing=\(controller.isPlaying ? 1 : 0) refused=\(controller.fullscreenRefused)")
            }
            .allowsHitTesting(false)
        }
        #endif
    }
}

/// Hears taps on the web view without taking them from YouTube's player (R-13: a tap brings the Exit button back).
final class TapRelay: NSObject, UIGestureRecognizerDelegate {
    private var recognizer: UITapGestureRecognizer?
    private var onTap: (() -> Void)?

    func attach(to view: UIView, onTap: @escaping () -> Void) {
        detach()
        self.onTap = onTap
        let r = UITapGestureRecognizer(target: self, action: #selector(tapped))
        r.cancelsTouchesInView = false
        r.delaysTouchesBegan = false
        r.delaysTouchesEnded = false
        r.delegate = self
        view.addGestureRecognizer(r)
        recognizer = r
    }

    func detach() {
        if let r = recognizer { r.view?.removeGestureRecognizer(r) }
        recognizer = nil
        onTap = nil
    }

    @objc private func tapped() { onTap?() }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// TT-4, R-11: Tabletop video, for update videos and trailers alike. Pre-play and playing are one screen (Iris, 20 Nov): the
/// standing half shows our own art until Play is pressed, then YouTube's player, unobscured and with its own branding (YouTube
/// API terms); the flat half holds the only controls. The video is drawn behind the arrangement, at the frame its stage
/// placeholder measures, with its mirror at the top of the lower half (the hinge band stays unpainted), under the fade and
/// behind the transport.
struct TabletopVideoStage: View {
    var controller: YouTubeController
    var video: ReleaseVideo
    var game: CatalogGame?
    var gameName: String
    /// The update the video belongs to; nil for a trailer, which has no Watch along.
    var release: Release?
    var onClose: () -> Void
    @AppStorage(VideoReflection.key) private var reflectionMode = VideoReflection.defaultOn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var stageVideo: CGRect?
    @State private var lowerTop: CGFloat?
    @State private var playerHeight: CGFloat = 0
    /// What the replicator reports it is drawing (QA audit, R-11).
    @State private var mirrorDrawn = false
    /// The player's origin on screen, so the audit reports the video and band in window points.
    @State private var playerOrigin: CGPoint = .zero
    private var auditGeometry: String {
        guard let v = stageVideo else { return "" }
        let top = lowerTop ?? v.maxY
        return MirrorAudit.geometry(video: v.offsetBy(dx: playerOrigin.x, dy: playerOrigin.y), bandTop: top + playerOrigin.y,
                                    band: VideoReflection.band(lowerHalf: playerHeight - top, tallIdle: tallIdle, controlsShown: controlsShown))
    }

    /// TT-4: shown or faded, owned here so the mirror's strength follows the controls (spec 5, mirror link).
    @State private var controlsShown = true
    @AppStorage(VideoReflection.idleKey) private var tallIdle = false

    var body: some View {
        let mirror = VideoReflection.shows(pose: .tabletop, setting: reflectionMode, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
        let live = mirror && controller.started
        ZStack(alignment: .topLeading) {
            // The stage on the bg token; the screen is pinned dark (Iris on #552), so it resolves to the dark bg.
            PlayscribeRole.bg.ignoresSafeArea()
            if let v = stageVideo {
                // The reflection starts where the lower half starts, directly under the video on the fold (spec 3 and 4).
                let top = lowerTop ?? v.maxY
                let band = VideoReflection.band(lowerHalf: playerHeight - top, tallIdle: tallIdle, controlsShown: controlsShown)
                ZStack {
                    // Before Play no player is on screen at all: our art, never a black box or YouTube's start screen.
                    VideoSurface(webView: controller.webView)
                        .background(.black)
                        .opacity(controller.playerShown ? 1 : 0)
                    if !controller.playerShown { VideoPoster(asset: video.posterAsset, game: game) }
                }
                .frame(width: v.width, height: v.height)
                .offset(x: v.minX, y: v.minY)
                // The stage is view only: the video behind it takes no touches either (TT-1).
                .allowsHitTesting(false)
                if live, band > 0 {
                    VideoMirrorStrip(source: controller.webView, band: band) { mirrorDrawn = $0 }
                        .frame(width: v.width, height: band)
                        .mirrorFinish(controlsShown: controlsShown)
                        .offset(x: v.minX, y: top)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: controlsShown)
                }
            }
            ArrangementView {
                TabletopTransport(controller: controller, video: video, game: gameName, release: release, controlsShown: $controlsShown,
                                  onClose: onClose)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("player")).minY } action: { lowerTop = $0 }
            } secondary: {
                // One column (spec 3): the video spans from the leading edge to the rail, as the controls below do, and stands
                // on the fold. The rail's column above the fold stays empty.
                Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("player")) } action: { stageVideo = $0 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.trailing, TabletopRail.width)
                    .allowsHitTesting(false)
            }
            .arrangementViewStyle(.overlay)
            MirrorAudit(on: live && mirrorDrawn && VideoReflection.band(lowerHalf: playerHeight - (lowerTop ?? playerHeight), tallIdle: tallIdle, controlsShown: controlsShown) > 0,
                        geometry: auditGeometry)
        }
        .coordinateSpace(.named("player"))
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { playerOrigin = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { playerHeight = $0 }
        // A screen for watching: dark in light and dark mode, so the white text, the grey and the rail's bar all hold (Iris on #552).
        .environment(\.colorScheme, .dark)
    }
}

/// VB-3, R-11 (Mac at c072400: outside Tabletop, Closed landscape and Open portrait showed YouTube's own start screen, with its
/// red button and "Watch on YouTube"): in every pose, until the video plays, the player shows our poster and our Play, never
/// YouTube's start screen. After Play, YouTube's player shows unobscured with its own controls (YouTube API terms). Play is
/// disabled until the player is ready; after it is pressed a spinner shows until the video starts.
struct VideoStartCover: View {
    var controller: YouTubeController
    var posterAsset: String?
    var game: CatalogGame?
    var body: some View {
        if !controller.playerShown {
            ZStack {
                VideoPoster(asset: posterAsset, game: game)
                Color.black.opacity(0.25).accessibilityHidden(true)
                if controller.playRequested {
                    ProgressView().controlSize(.large).tint(.white).accessibilityLabel("Loading video")
                } else {
                    Button(action: controller.playPause) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .frame(width: 64, height: 64)
                            .background(PlayscribeRole.action, in: Circle())
                            .foregroundStyle(PlayscribeRole.onAction)
                    }
                    .accessibilityLabel("Play")
                    .accessibilityIdentifier("videoPlay")
                    .disabled(!controller.ready)
                    .opacity(controller.ready ? 1 : 0.5)
                    .tappableFrame()
                }
            }
        }
    }
}

/// The Tabletop stage before Play: the update video's own poster, else the game's key art cropped to 16:9 (Iris, 20 Nov).
struct VideoPoster: View {
    var asset: String?
    var game: CatalogGame?
    var body: some View {
        Group {
            if let asset {
                ZStack { Color.black; Image(asset).resizable().scaledToFit() }
            } else {
                ArtView(asset: game?.keyArtAsset, game: game).clipped()
            }
        }
        // Decoration: VoiceOver would read the asset's name (Iris, 20 Nov).
        .accessibilityHidden(true)
    }
}

struct VideoCaption: View {
    var video: ReleaseVideo
    var game: String
    /// The player's reported length, used when the video has no stored one (trailers). The line is always there (it holds the
    /// game's name), so nothing moves when the length arrives (Iris, 20 Nov).
    var length: Double = 0
    /// True in Tabletop, over the mirror: the grey is white at 85%, which keeps 4.5:1 over a mirrored white frame at the mirror's
    /// 20% with no plate behind it (Iris, reflection-0.6 spec 4).
    var overMirror = false
    private var detail: String {
        [game, video.duration ?? (length > 0 ? PlayerTime.format(length) : nil)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(video.label).font(PlayscribeFont.headline).foregroundStyle(.white)
            Text(detail.isEmpty ? " " : detail)
                .font(PlayscribeFont.subheadline)
                // Over the mirror the grey is lifted so it keeps 4.5:1 on any frame (Mac, 12 Nov: 4.1 and 3.2 with .secondary).
                .foregroundStyle(overMirror ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(PlayscribeRole.textSecondary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Watch along": the video's timestamps when there are any (tap to seek), else the release's
/// key changes, plus a link to the full notes (TT-4, VB-2).
struct WatchAlong: View {
    var controller: YouTubeController
    var release: Release
    var openNotes: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Watch along").font(PlayscribeFont.caption).tracking(1).foregroundStyle(PlayscribeRole.textTertiary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array((release.keyChanges ?? []).enumerated()), id: \.offset) { _, k in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(PlayscribeRole.action).frame(width: 6, height: 6).accessibilityHidden(true)
                        Text(k).font(PlayscribeFont.subheadline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                Button("Read the full notes", action: openNotes)
                    .font(PlayscribeFont.subheadline.weight(.semibold))
                    .hitTarget()
                    .tappableFrame()
            }
            .padding(20)
        }
        .foregroundStyle(.white)
    }
}

/// TT-4: the only custom transport. Title, scrubber with times, then captions, back 10 s,
/// play/pause (64 pt), forward 10 s and volume, in the system player's order; Close tops the rail.
struct TabletopTransport: View {
    @Bindable var controller: YouTubeController
    var video: ReleaseVideo
    var game: String
    /// The update the video belongs to; nil for a trailer, which has no Watch along.
    var release: Release?
    /// TT-4 (Terry's Duo, 21 Nov: the controls "look like they should dim or could be dismissed but they can't"; Iris,
    /// reflection-0.6 spec 5). While the video plays they fade after 4 s with no touch, leaving the picture, its reflection, the
    /// rail and a 2 pt progress line. A tap anywhere in the lower half beside the rail brings them back, and that first tap does
    /// nothing else. Paused, buffering, ended, or with VoiceOver or Switch Control on, they stay.
    @Binding var controlsShown: Bool
    var onClose: () -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hideTask: Task<Void, Never>?
    /// True once the fade-out has finished: the controls are then hidden outright, out of the accessibility tree and of reach
    /// (Mac at 5ddf0d74: under opacity 0 and accessibilityHidden, XCUITest still found Pause).
    @State private var controlsGone = false
    static let hideAfter: Duration = .seconds(4)

    /// Whether the controls may fade now (spec 5): only while playing, and never under VoiceOver or Switch Control.
    static func autoHides(playing: Bool, voiceOver: Bool, switchControl: Bool) -> Bool {
        playing && !voiceOver && !switchControl
    }

    private var hides: Bool { Self.autoHides(playing: controller.isPlaying, voiceOver: voiceOver, switchControl: switchControl) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if controlsGone { controls.hidden() } else { controls }
            }
                .opacity(controlsShown ? 1 : 0)
                .allowsHitTesting(controlsShown)
                .accessibilityHidden(!controlsShown)
                // Any touch on a control counts as use and restarts the 4 s; it never blocks the control itself.
                .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in wake() })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .top) {
                    if !controlsShown {
                        ZStack(alignment: .top) {
                            // The first tap only reveals (spec 5): this layer takes it, so no control under it fires.
                            Color.clear.contentShape(Rectangle()).onTapGesture { wake() }
                                .accessibilityLabel("Show controls")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("showControls")
                            ProgressHairline(progress: controller.duration > 0 ? controller.current / controller.duration : 0)
                                .accessibilityHidden(true)
                        }
                    }
                }
            // The rail: Close at its top (TT-4), identical in every pose; it stays when the controls fade.
            VStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.title3).frame(width: 48, height: 48)
                }
                .accessibilityLabel("Close")
                .tappableFrame()
                Spacer()
            }
            .frame(width: TabletopRail.width)
            .padding(.top, 8)
            .background(.bar)
        }
        .foregroundStyle(.white)
        .onChange(of: hides, initial: true) { _, on in on ? schedule() : show() }
        .onDisappear { hideTask?.cancel() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoCaption(video: video, game: game, length: controller.duration, overMirror: true)
            Slider(value: Binding(get: { controller.current }, set: { controller.seek(to: $0) }), in: 0...max(1, controller.duration))
                .accessibilityLabel("Playback position")
                // Spoken as time, not a percent, and the printed times below are not read a second time.
                .accessibilityValue("\(PlayerTime.spoken(controller.current)) of \(PlayerTime.spoken(controller.duration))")
                .tappableFrame()
            HStack {
                Text(PlayerTime.format(controller.current))
                Spacer()
                Text("-" + PlayerTime.format(max(0, controller.duration - controller.current)))
            }
            .font(PlayscribeFont.caption.monospacedDigit())
            // White at 85% keeps 4.5:1 over the mirror at 20% with no plate (spec 4).
            .foregroundStyle(Color.white.opacity(0.85))
            .accessibilityHidden(true)
            HStack(spacing: 0) {
                transportButton(controller.captionsOn ? "captions.bubble.fill" : "captions.bubble", "Captions", action: controller.toggleCaptions)
                    .accessibilityValue(controller.captionsOn ? "On" : "Off")
                Spacer()
                transportButton("gobackward.10", "Back 10 seconds") { controller.skip(-10) }
                Spacer()
                Button(action: controller.playPause) {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .frame(width: 64, height: 64)
                        .background(PlayscribeRole.action, in: Circle())
                        .foregroundStyle(PlayscribeRole.onAction)
                }
                .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("videoPlay")
                // Until the player is ready a press would do nothing (Quinn on #552).
                .disabled(!controller.ready)
                .opacity(controller.ready ? 1 : 0.5)
                .tappableFrame()
                Spacer()
                transportButton("goforward.10", "Forward 10 seconds") { controller.skip(10) }
                Spacer()
                transportButton(controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                controller.isMuted ? "Unmute" : "Mute", action: controller.toggleMute)
            }
            if let release {
                WatchAlong(controller: controller, release: release, openNotes: onClose)
                    .padding(.horizontal, -20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func wake() {
        show()
        if hides { schedule() }
    }

    private func show() {
        hideTask?.cancel()
        controlsGone = false
        guard !controlsShown else { return }
        // Fade in 200 ms; under Reduce Motion an instant change (spec 5).
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { controlsShown = true }
    }

    private func schedule() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: Self.hideAfter)
            guard !Task.isCancelled, hides else { return }
            // Fade out 300 ms (spec 5), then hide outright.
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { controlsShown = false } completion: {
                if !controlsShown { controlsGone = true }
            }
        }
    }

    private func transportButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.title3).frame(width: 48, height: 48) }
            .accessibilityLabel(label)
            .tappableFrame()
    }
}

/// TT-4: while the controls are faded, a 2 pt accent line along the top of the lower half shows how far the video has played.
/// View only.
struct ProgressHairline: View {
    var progress: Double
    var body: some View {
        GeometryReader { g in
            Rectangle().fill(PlayscribeRole.action)
                .frame(width: g.size.width * min(1, max(0, progress)), height: 2)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}

enum PlayerTime {
    /// "one minute, twenty-three seconds", for VoiceOver.
    static func spoken(_ t: Double) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .spellOut
        f.allowedUnits = [.minute, .second]
        f.zeroFormattingBehavior = .dropAll
        return f.string(from: max(0, t.rounded())) ?? ""
    }

    static func format(_ t: Double) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// R-12. The one hand-off (Terry, 20 Nov: "If video unavailable then it must instead say open in YouTube"): a video whose owner
/// blocks playing it in other apps offers Open in YouTube. Opened straight through the system, never through the app's openURL
/// handler, which would route a YouTube link back into this player.
struct VideoUnavailable: View {
    var videoID: String
    /// The video's name, shown above the reason so the person knows which video this is (Iris on #554).
    var title: String? = nil
    /// The player's error code, when it gave one.
    var code: Int? = nil
    /// False where the navigation bar already carries Close (every pose but Tabletop), so Close appears once.
    var showsClose = true
    var onClose: () -> Void
    static func blocksEmbedding(_ code: Int?) -> Bool { code == 101 || code == 150 }
    var body: some View {
        // Open in YouTube sits directly under the reason, not at the foot of the screen (Iris on #554).
        ContentUnavailableView {
            Label(Self.blocksEmbedding(code) ? "This video plays only on YouTube" : "This video can’t play here", systemImage: "play.slash")
        } description: {
            VStack(spacing: 6) {
                if let title, !title.isEmpty { Text(title).font(PlayscribeFont.headline).foregroundStyle(PlayscribeRole.textPrimary) }
                if Self.blocksEmbedding(code) { Text("Its owner doesn’t allow it to play in other apps.") }
            }
        } actions: {
            if let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)") {
                Button("Open in YouTube") { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeRole.onAction)
                    .tappableFrame()
            }
            if showsClose { Button("Close", action: onClose).hitTarget() }
        }
    }
}

/// bug-071: full screen from portrait asks the scene for landscape, as YouTube and Netflix do, and Exit turns it back. A request
/// only: the scene's supported orientations still decide, so a later turn of the phone follows the device as before.
@MainActor
enum VideoOrientation {
    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
    }

    static var isPortrait: Bool { scene?.effectiveGeometry.interfaceOrientation.isPortrait ?? false }

    static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in NSLog("videoOrientation: \(error)") }
    }
}

/// bug-071, Iris's specBands: our controls in full screen. They live only in the black letterbox bands, never in front of the
/// player (YouTube RMF), as plain white glyphs with no glass. Top band: Exit full screen and the title. Bottom band: back 10,
/// play/pause, forward 10, elapsed, the scrubber and remaining. In Book the transport is on the leading page and the scrubber on
/// the trailing one, nothing within 8 pt of the division. They fade together (opacity, 0.25 s) 3 s after the last touch while
/// playing, and show again on a tap in a band; a tap on the picture is YouTube's (policy_touches on the card), so it never
/// shows ours. While hidden, the first band tap only shows them. VoiceOver and Switch Control keep them shown.
struct FullScreenBands: View {
    @Bindable var controller: YouTubeController
    var title: String
    /// bug-073: counts taps on the picture; each one shows the controls like a band tap.
    var pictureTaps = 0
    /// The picture, the screen and the safe insets, in screen coordinates.
    var picture: CGRect
    var screen: CGSize
    var safe: EdgeInsets
    /// Book: the division in screen coordinates.
    var division: CGRect?
    /// Camera housings in screen coordinates: the control rows keep clear of them.
    var housings: [CGRect] = []
    var onExit: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = true
    @State private var scrubbing = false
    @State private var hideTask: Task<Void, Never>?
    /// QA: band taps seen, for the cloud fullscreen scenario.
    @State private var wakes = 0
    static let hideAfter: Duration = .seconds(3)
    /// Nothing within this of the division (Iris).
    static let foldClearance: CGFloat = 8

    /// The rows the controls sit in, in screen coordinates. Without a division: one top row and one bottom row across the safe
    /// width. With one: the top row and the transport end before the division, and the timeline starts after it.
    struct Layout: Equatable {
        var top: CGRect
        var transport: CGRect
        var timeline: CGRect?
    }

    /// Clearance between a control row and a camera housing (Iris, bug-071: Exit starts at x 92 or more past an 84 pt housing).
    static let housingClearance: CGFloat = 8

    static func layout(picture: CGRect, screen: CGSize, safe: EdgeInsets, division: CGRect?, avoiding housings: [CGRect] = []) -> Layout {
        let left = safe.leading + 12, right = screen.width - safe.trailing - 12
        // Vertically centred in a band; in a deep band (portrait under rotation lock) at the edge nearest the picture (Iris).
        let topBand = picture.minY, bottomBand = screen.height - picture.maxY
        let topY = topBand > 2 * 44 + 16 ? picture.minY - 44 - 8 : (topBand - 44) / 2
        let bottomY = bottomBand > 2 * 44 + 16 ? picture.maxY + 8 : picture.maxY + (bottomBand - 44) / 2
        // A row whose band a housing reaches into starts, or ends, clear of it on that side (spec: no control or text in it).
        func row(_ x0: CGFloat, _ x1: CGFloat, y: CGFloat) -> CGRect {
            var a = x0, b = x1
            for h in housings where h.minY < y + 44 && h.maxY > y && h.minX < b && h.maxX > a {
                if h.midX < screen.width / 2 { a = max(a, h.maxX + housingClearance) } else { b = min(b, h.minX - housingClearance) }
            }
            return CGRect(x: a, y: y, width: max(0, b - a), height: 44)
        }
        if let d = division {
            let leadEnd = d.minX - foldClearance, trailStart = d.maxX + foldClearance
            return Layout(top: row(left, leadEnd, y: topY), transport: row(left, leadEnd, y: bottomY),
                          timeline: row(trailStart, right, y: bottomY))
        }
        return Layout(top: row(left, right, y: topY), transport: row(left, right, y: bottomY), timeline: nil)
    }

    private var hides: Bool { controller.isPlaying && !scrubbing && !voiceOver && !switchControl && !Self.qaStay }

    /// At the end of the video the bands stay up and Play becomes Replay (Iris, #655), over YouTube's end screen.
    private var ended: Bool { !controller.isPlaying && controller.duration > 0 && controller.current >= controller.duration - 0.5 }

    /// Internal builds: -qaBandsStay YES keeps the band controls up, so stills can show them (Iris, bug-071).
    static var qaStay: Bool {
        #if INTERNAL
        UserDefaults.standard.bool(forKey: "qaBandsStay")
        #else
        false
        #endif
    }

    var body: some View {
        let l = Self.layout(picture: picture, screen: screen, safe: safe, division: division, avoiding: housings)
        ZStack(alignment: .topLeading) {
            // The bands themselves take taps (to show the controls), never the picture.
            bandCatcher(CGRect(x: 0, y: 0, width: screen.width, height: picture.minY))
            bandCatcher(CGRect(x: 0, y: picture.maxY, width: screen.width, height: screen.height - picture.maxY))
            // bug-073 (Terry, beta 6: no way to close full screen in Closed once the controls faded): Exit never fades. It sits in
            // the top band, never over the picture, so it can always be found, tapped and reached by VoiceOver.
            glyph("chevron.down", "Exit full screen", id: "videoExitFullScreen", action: onExit)
                .offset(x: l.top.minX, y: l.top.minY)
            Group {
                HStack(spacing: 12) {
                    Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)   // Exit's place, drawn above
                    Text(title)
                        .font(PlayscribeFont.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }
                .frame(width: l.top.width, height: 44)
                .offset(x: l.top.minX, y: l.top.minY)
                HStack(spacing: 4) {
                    glyph("gobackward.10", "Back 10 seconds", id: "videoBack10") { controller.skip(-10) }
                    Group {
                        if ended {
                            glyph("arrow.counterclockwise", "Replay", id: "videoPlayPause") { controller.seek(to: 0); controller.playPause() }
                        } else {
                            glyph(controller.isPlaying ? "pause.fill" : "play.fill", controller.isPlaying ? "Pause" : "Play",
                                  id: "videoPlayPause", action: controller.playPause)
                        }
                    }
                    .disabled(!controller.ready)
                    glyph("goforward.10", "Forward 10 seconds", id: "videoForward10") { controller.skip(10) }
                    if l.timeline == nil { timeline } else { Spacer(minLength: 0) }
                }
                .frame(width: l.transport.width, height: 44)
                .offset(x: l.transport.minX, y: l.transport.minY)
                if let t = l.timeline {
                    timeline.frame(width: t.width, height: 44).offset(x: t.minX, y: t.minY)
                }
            }
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
        }
        .frame(width: screen.width, height: screen.height, alignment: .topLeading)
        .foregroundStyle(.white)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        #if INTERNAL
        .overlay(alignment: .topLeading) {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("qaBands")
                .accessibilityValue("shown=\(shown ? 1 : 0) wakes=\(wakes)")
                .offset(x: 4, y: 2)
        }
        #endif
        .onChange(of: hides, initial: true) { _, on in on ? schedule() : show() }
        .onChange(of: pictureTaps) { wake() }
        .onDisappear { hideTask?.cancel() }
    }

    private var timeline: some View {
        HStack(spacing: 8) {
            Text(PlayerTime.format(controller.current))
            BandScrubber(controller: controller, scrubbing: $scrubbing)
            Text("-" + PlayerTime.format(max(0, controller.duration - controller.current)))
        }
        .font(PlayscribeFont.footnote.monospacedDigit())
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func bandCatcher(_ r: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { wake() }
            .frame(width: r.width, height: max(0, r.height))
            .offset(x: r.minX, y: r.minY)
            .accessibilityHidden(true)
    }

    private func glyph(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button { action(); wake() } label: {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
        .tappableFrame()
    }

    private func wake() {
        wakes += 1
        show()
        if hides { schedule() }
    }

    private func show() {
        hideTask?.cancel()
        guard !shown else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { shown = true }
    }

    private func schedule() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: Self.hideAfter)
            guard !Task.isCancelled, hides else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { shown = false }
        }
    }
}

/// specBands scrubber: a 4 pt track (white 30%) with white fill and a 12 pt thumb that grows to 20 pt while dragging, in a
/// 44 pt hit area. VoiceOver: adjustable in 10 s steps, read as time.
struct BandScrubber: View {
    @Bindable var controller: YouTubeController
    @Binding var scrubbing: Bool
    @State private var dragTime: Double?

    var body: some View {
        GeometryReader { geo in
            let d = max(1, controller.duration)
            let t = dragTime ?? controller.current
            let x = geo.size.width * CGFloat(min(1, max(0, t / d)))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                Capsule().fill(.white).frame(width: x, height: 4)
                Circle().fill(.white)
                    .frame(width: scrubbing ? 20 : 12, height: scrubbing ? 20 : 12)
                    .offset(x: x - (scrubbing ? 10 : 6))
                    .animation(.easeOut(duration: 0.15), value: scrubbing)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    scrubbing = true
                    dragTime = Double(min(1, max(0, g.location.x / max(1, geo.size.width)))) * d
                }
                .onEnded { _ in
                    if let dragTime { controller.seek(to: dragTime) }
                    dragTime = nil
                    scrubbing = false
                })
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(PlayerTime.spoken(controller.current)) of \(PlayerTime.spoken(controller.duration))")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: controller.skip(10)
            case .decrement: controller.skip(-10)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("videoScrubber")
        .tappableFrame()
    }
}
