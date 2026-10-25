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

    init(videoID: String) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let content = WKUserContentController()
        config.userContentController = content
        webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        super.init()
        content.add(self, name: "player")
        webView.loadHTMLString(Self.html(videoID), baseURL: URL(string: "https://playscribe.app"))
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
    var captionsOn = true
    func toggleCaptions() {
        captionsOn.toggle()
        run(captionsOn ? "player.loadModule('captions')" : "player.unloadModule('captions')")
    }
    func stop() { run("player.stopVideo()") }
    private func run(_ js: String) { webView.evaluateJavaScript(js) }

    static func html(_ id: String) -> String {
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
            playerVars:{playsinline:1,controls:1,cc_load_policy:1,rel:0,modestbranding:1,iv_load_policy:3,origin:'https://playscribe.app'},
            events:{onReady:function(){post({event:'ready',duration:player.getDuration()})},
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
            // TT-4: the standing half shows only the video; the flat half holds the transport.
            ArrangementView {
                TabletopTransport(controller: controller, video: video, game: gameName, release: release, onClose: close)
            } secondary: {
                surface
                    .overlay { if !controller.started { PosterCover(video: video) } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                    .allowsHitTesting(false)
            }
            .arrangementViewStyle(.overlay)
        case .book:
            // VB-2: the video and its details on the left page; Watch along on the right.
            if let fold = duo.division {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        surface
                        VideoCaption(video: video, game: gameName)
                            .padding(.horizontal, 16)
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
            VStack(spacing: 12) {
                surface.frame(maxWidth: .infinity)
                VideoCaption(video: video, game: gameName).padding(.horizontal, 16)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(video.label).font(PlayscribeFont.headline).foregroundStyle(.white)
            Text([game, video.duration].compactMap { $0 }.joined(separator: " · "))
                .font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
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
                Text("WATCH ALONG").font(PlayscribeFont.caption).tracking(1).foregroundStyle(PlayscribeColor.textTertiary)
                ForEach(Array((release.keyChanges ?? []).enumerated()), id: \.offset) { _, k in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(PlayscribeColor.accent).frame(width: 6, height: 6)
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
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VideoCaption(video: video, game: game)
                Slider(value: Binding(get: { controller.current }, set: { controller.seek(to: $0) }), in: 0...max(1, controller.duration))
                    .accessibilityLabel("Playback position")
                    .tappableFrame()
                HStack {
                    Text(PlayerTime.format(controller.current))
                    Spacer()
                    Text("-" + PlayerTime.format(max(0, controller.duration - controller.current)))
                }
                .font(PlayscribeFont.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    transportButton(controller.captionsOn ? "captions.bubble.fill" : "captions.bubble", "Captions", action: controller.toggleCaptions)
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
