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
                self.isPlaying = state == 1
                if state == 1 { self.started = true }
                // 1 playing, 3 buffering: the player has the picture, so the stage can show it (Iris, 20 Nov).
                if state == 1 || state == 3 { self.playerShown = true }
            case "time": self.current = time ?? 0; if let duration, duration > 0 { self.duration = duration }
            case "error": self.failed = true
            case "fullscreenRefused": self.fullscreenRefused += 1
            default: break
            }
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
        run("setControls(\(on ? 1 : 0))")
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
        function setControls(c){
          if(c===controls){return}
          controls=c;
          if(!player||!player.getCurrentTime){return}
          var t=player.getCurrentTime(), play=player.getPlayerState()===1;
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
    var body: some View {
        NavigationStack {
            DuoReader { duo in
                let release = model.release(gameID, releaseID)
                Group {
                    if let release, let video = release.video, let controller {
                        if controller.failed {
                            VideoUnavailable { close() }
                        } else {
                            layout(duo: duo, release: release, video: video, controller: controller)
                        }
                    } else {
                        VideoUnavailable { close() }
                    }
                }
                .background(.black)
                .onChange(of: [duo.pose == .tabletop, controller != nil], initial: true) { controller?.setNativeControls(duo.pose != .tabletop) }
                .toolbarVisibility(duo.pose == .tabletop ? .hidden : .automatic, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: close) { Label("Close", systemImage: "xmark") }
                    }
                }
            }
        }
        .onAppear {
            if controller == nil, let id = model.release(gameID, releaseID)?.video?.youtubeID {
                controller = YouTubeController(videoID: id, nativeControls: model.livePose != .tabletop)
            }
        }
    }

    @ViewBuilder
    private func layout(duo: DuoContext, release: Release, video: ReleaseVideo, controller: YouTubeController) -> some View {
        // A web view has no intrinsic size, so a 16:9 box carries the size and the view fills it.
        let surface = Color.black.aspectRatio(16 / 9, contentMode: .fit).overlay { WebSurface(webView: controller.webView) }
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
            // VB-3: full display, the player's own controls.
            VStack(spacing: 0) {
                surface.frame(maxWidth: .infinity)
                VideoCaption(video: video, game: gameName).padding(.horizontal, 16).padding(.top, 12)
            }
            .frame(maxHeight: .infinity, alignment: duo.pose == .closed ? .top : .center)
            .overlay(alignment: .topLeading) { MirrorAudit(on: false) }
        }
    }

    private func close() {
        controller?.stop()
        dismiss()
    }
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
                                    band: VideoReflection.band(lowerHalf: playerHeight - top))
    }

    var body: some View {
        let mirror = VideoReflection.shows(pose: .tabletop, setting: reflectionMode, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
        let live = mirror && controller.started
        ZStack(alignment: .topLeading) {
            Color.ink0.ignoresSafeArea()
            if let v = stageVideo {
                let top = lowerTop ?? v.maxY
                ZStack {
                    // Before Play no player is on screen at all: our art, never a black box or YouTube's start screen.
                    MirroredVideoSurface(webView: controller.webView, mirrored: live, gap: max(0, top - v.maxY)) { mirrorDrawn = $0 }
                        .background(.black)
                        .opacity(controller.playerShown ? 1 : 0)
                    if !controller.playerShown { VideoPoster(asset: video.posterAsset, game: game) }
                }
                .frame(width: v.width, height: v.height)
                .offset(x: v.minX, y: v.minY)
                // The stage is view only: the video behind it takes no touches either (TT-1).
                .allowsHitTesting(false)
                if live {
                    MirrorFade(band: VideoReflection.band(lowerHalf: playerHeight - top))
                        .frame(width: v.width, height: v.height)
                        .offset(x: v.minX, y: top)
                }
            }
            ArrangementView {
                TabletopTransport(controller: controller, video: video, game: gameName, release: release, overMirror: live, onClose: onClose)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("player")).minY } action: { lowerTop = $0 }
            } secondary: {
                Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("player")) } action: { stageVideo = $0 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            .arrangementViewStyle(.overlay)
            MirrorAudit(on: mirrorDrawn && VideoReflection.band(lowerHalf: playerHeight - (lowerTop ?? playerHeight)) > 0,
                        geometry: auditGeometry)
        }
        .coordinateSpace(.named("player"))
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { playerOrigin = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { playerHeight = $0 }
        // A screen for watching: dark in light and dark mode, so the white text, the grey and the rail's bar all hold (Iris on #552).
        .environment(\.colorScheme, .dark)
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
    /// True when the mirror sits behind the caption: the plate hugs the text, not the whole row, so the mirror shows beside
    /// and below it (the full-width plate darkened the band to 10 to 12 of 255, 12 Nov).
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
                .foregroundStyle(overMirror ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary))
        }
        .overMirror(overMirror)
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
                Text("Watch along").font(PlayscribeFont.caption).tracking(1).foregroundStyle(PlayscribeColor.textTertiary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array((release.keyChanges ?? []).enumerated()), id: \.offset) { _, k in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(PlayscribeColor.accent).frame(width: 6, height: 6).accessibilityHidden(true)
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
    /// True when the mirror sits behind this column (R-11), so its text gets the plate and the lifted grey.
    var overMirror = false
    var onClose: () -> Void

    var body: some View {
        // The mirror sits behind this whole column, so the text on it gets the plate and the lifted grey (R-11; Mac 12 Nov:
        // the Tabletop subtitle measured 3.3:1 median, 2.3:1 worst).
        let over = overMirror
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VideoCaption(video: video, game: game, length: controller.duration, overMirror: over)
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
                .foregroundStyle(over ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                .overMirror(over)
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
                            .background(PlayscribeColor.accent, in: Circle())
                            .foregroundStyle(PlayscribeColor.onAccent)
                    }
                    .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
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
            // The rail: Close at its top (TT-4).
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
    }

    private func transportButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.title3).frame(width: 48, height: 48) }
            .accessibilityLabel(label)
            .tappableFrame()
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

/// R-12. No hand-off to YouTube (Terry, 20 Nov: every video plays in our own player): a video that cannot play here says so.
struct VideoUnavailable: View {
    var onClose: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView("Video unavailable", systemImage: "play.slash", description: Text("This video can’t play in Playscribe."))
            Button("Close", action: onClose).hitTarget()
        }
    }
}
