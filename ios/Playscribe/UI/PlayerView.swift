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

    /// Settings key for "Autoplay videos". Off by default (R-11, G-9).
    static let autoplayKey = "autoplayVideos"
    /// True when videos should start on their own: the setting is on and Reduce Motion is off (G-9).
    static var autoplayEnabled: Bool {
        UserDefaults.standard.bool(forKey: autoplayKey) && !UIAccessibility.isReduceMotionEnabled
    }

    init(videoID: String, autoplay: Bool = YouTubeController.autoplayEnabled) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // D-11: the trailer keeps playing in Picture in Picture when the person leaves the app.
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let content = WKUserContentController()
        config.userContentController = content
        webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        super.init()
        content.add(self, name: "player")
        webView.loadHTMLString(Self.html(videoID, captions: captionsOn, autoplay: autoplay), baseURL: URL(string: "https://playscribe.app"))
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any] else { return }
            let event = body["event"] as? String
            let state = body["state"] as? Int
            let time = body["time"] as? Double
            let duration = body["duration"] as? Double
            switch event {
            case "ready": self.ready = true; self.duration = duration ?? 0
            case "state": self.isPlaying = state == 1; if state == 1 { self.started = true }
            case "time": self.current = time ?? 0; if let duration, duration > 0 { self.duration = duration }
            case "error": self.failed = true
            default: break
            }
        }
    }

    func playPause() { run(isPlaying ? "player.pauseVideo()" : "player.playVideo()") }
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
    private func run(_ js: String) { webView.evaluateJavaScript(js) }

    static func html(_ id: String, captions: Bool, autoplay: Bool = false) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body><div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function post(m){window.webkit.messageHandlers.player.postMessage(m)}
        function onYouTubeIframeAPIReady(){
          player=new YT.Player('p',{videoId:'\(id)',host:'https://www.youtube-nocookie.com',
            playerVars:{playsinline:1,controls:1,cc_load_policy:\(captions ? 1 : 0),autoplay:\(autoplay ? 1 : 0),rel:0,modestbranding:1,iv_load_policy:3,origin:'https://playscribe.app'},
            events:{onReady:function(){post({event:'ready',duration:player.getDuration()});\(autoplay ? "player.playVideo();" : "")},
                    onStateChange:function(e){post({event:'state',state:e.data})},
                    onError:function(e){post({event:'error',code:e.data})}}});
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
    @AppStorage(VideoReflection.key) private var reflectionMode = VideoReflection.defaultOn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Tabletop (R-11): the video's frame on the stage and the top of the lower half, both in the "player" space, so the video
    /// and its mirror can be drawn behind the arrangement, in one replicator, across the fold.
    @State private var stageVideo: CGRect?
    @State private var lowerTop: CGFloat?

    var body: some View {
        NavigationStack {
            DuoReader { duo in
                let release = model.release(gameID, releaseID)
                Group {
                    if let release, let video = release.video, let controller {
                        if controller.failed {
                            VideoUnavailable(url: video.watchURL) { close() }
                        } else {
                            layout(duo: duo, release: release, video: video, controller: controller)
                        }
                    } else {
                        VideoUnavailable(url: release?.video?.watchURL) { close() }
                    }
                }
                .background(.black)
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
                controller = YouTubeController(videoID: id)
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
            // TT-4: the standing half shows only the video; the flat half holds the transport. R-11: the video itself is drawn
            // behind the arrangement, at the frame its stage placeholder measures, inside a replicator whose mirror lands at the
            // top of the lower half (the hinge band stays unpainted), under the fade and behind the transport.
            let mirror = VideoReflection.shows(pose: duo.pose, setting: reflectionMode, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
            ZStack(alignment: .topLeading) {
                if let v = stageVideo {
                    let top = lowerTop ?? v.maxY
                    let live = mirror && controller.started
                    MirroredVideoSurface(webView: controller.webView, mirrored: live, gap: max(0, top - v.maxY))
                        .background(.black)
                        .overlay { if !controller.started { PosterCover(video: video) } }
                        .frame(width: v.width, height: v.height)
                        .offset(x: v.minX, y: v.minY)
                        // The stage is view only: the video behind it takes no touches either (TT-1).
                        .allowsHitTesting(false)
                    if live {
                        MirrorFade()
                            .frame(width: v.width, height: v.height)
                            .offset(x: v.minX, y: top)
                    }
                }
                ArrangementView {
                    TabletopTransport(controller: controller, video: video, game: gameName, release: release, overMirror: mirror, onClose: close)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("player")).minY } action: { lowerTop = $0 }
                } secondary: {
                    Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("player")) } action: { stageVideo = $0 }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
                .arrangementViewStyle(.overlay)
            }
            .coordinateSpace(.named("player"))
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
            }
        case .closed, .flat:
            // VB-3: full display, the player's own controls.
            VStack(spacing: 0) {
                surface.frame(maxWidth: .infinity)
                VideoCaption(video: video, game: gameName).padding(.horizontal, 16).padding(.top, 12)
            }
            .frame(maxHeight: .infinity, alignment: duo.pose == .closed ? .top : .center)
        }
    }

    private func close() {
        controller?.stop()
        dismiss()
    }
}

/// Covers YouTube's start screen on the Tabletop stage until playback begins.
struct PosterCover: View {
    var video: ReleaseVideo
    var body: some View {
        ZStack {
            Color.black
            if let poster = video.posterAsset { Image(poster).resizable().scaledToFit() }
        }
    }
}

struct VideoCaption: View {
    var video: ReleaseVideo
    var game: String
    /// True when the mirror sits behind the caption: the plate hugs the text, not the whole row, so the mirror shows beside
    /// and below it (the full-width plate darkened the band to 10 to 12 of 255, 12 Nov).
    var overMirror = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(video.label).font(PlayscribeFont.headline).foregroundStyle(.white)
            Text([game, video.duration].compactMap { $0 }.joined(separator: ", "))
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
                Text("WATCH ALONG").font(PlayscribeFont.caption).tracking(1).foregroundStyle(PlayscribeColor.textTertiary)
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
    var release: Release
    /// True when the mirror sits behind this column (R-11), so its text gets the plate and the lifted grey.
    var overMirror = false
    var onClose: () -> Void

    var body: some View {
        // The mirror sits behind this whole column, so the text on it gets the plate and the lifted grey (R-11; Mac 12 Nov:
        // the Tabletop subtitle measured 3.3:1 median, 2.3:1 worst).
        let over = overMirror
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VideoCaption(video: video, game: game, overMirror: over)
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
                    .tappableFrame()
                    Spacer()
                    transportButton("goforward.10", "Forward 10 seconds") { controller.skip(10) }
                    Spacer()
                    transportButton(controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                    controller.isMuted ? "Unmute" : "Mute", action: controller.toggleMute)
                }
                WatchAlong(controller: controller, release: release, openNotes: onClose)
                    .padding(.horizontal, -20)
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

/// R-12.
struct VideoUnavailable: View {
    var url: URL?
    var onClose: () -> Void
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView("Video unavailable", systemImage: "play.slash")
            if let url { Button("Watch on YouTube") { openURL(url) }.buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent) }
            Button("Close", action: onClose).hitTarget()
        }
    }
}
