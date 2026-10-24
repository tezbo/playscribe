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
            playerVars:{playsinline:1,controls:0,rel:0,modestbranding:1,iv_load_policy:3,origin:'https://playscribe.app'},
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
                if let video = release?.video, let controller {
                    if controller.failed {
                        VideoUnavailable(url: video.watchURL) { dismiss() }
                    } else {
                        // Tabletop: video above the fold, every control below it (R-11).
                        ArrangementView {
                            PlayerControls(controller: controller, title: video.label, game: model.game(gameID)?.name ?? "",
                                           onClose: tabletopClose(duo))
                                .padding(.trailing, duo.pose == .tabletop ? 8 : 0)
                        } secondary: {
                            WebSurface(webView: controller.webView)
                                // One player only: the release poster covers YouTube's own
                                // start screen until playback begins.
                                .overlay {
                                    if !controller.started {
                                        ZStack {
                                            Color.black
                                            if let poster = video.posterAsset { Image(poster).resizable().scaledToFit() }
                                        }
                                    }
                                }
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: videoAlignment(duo))
                                .background(.black)
                                .allowsHitTesting(false)
                        }
                        .arrangementViewStyle(.overlay)
                    }
                } else {
                    VideoUnavailable(url: release?.video?.watchURL) { dismiss() }
                }
            }
            .background(.black)
            // Tabletop keeps Close in the lower half with the other controls (G-4); elsewhere it
            // is the bar's cancellation action, at the top of the vertical axis (R-11).
            .toolbarVisibility(barVisibility(duo), for: .navigationBar)
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

    private func close() {
        controller?.stop()
        dismiss()
    }

    private func barVisibility(_ duo: DuoContext) -> Visibility { duo.pose == .tabletop ? .hidden : .automatic }

    private func videoAlignment(_ duo: DuoContext) -> Alignment { duo.pose == .closed ? .top : .center }

    private func tabletopClose(_ duo: DuoContext) -> (() -> Void)? {
        guard duo.pose == .tabletop else { return nil }
        return { close() }
    }
}

struct PlayerControls: View {
    @Bindable var controller: YouTubeController
    var title: String
    var game: String
    var onClose: (() -> Void)?
    @Environment(\.duo) private var duo

    var body: some View {
        VStack(spacing: 12) {
            // Closed: the controls sit right under the top-aligned video, not at the bottom.
            if duo.pose == .closed { Spacer().frame(height: closedVideoHeight) } else if duo.pose != .tabletop { Spacer() }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PlayscribeFont.headline)
                    Text(game).font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let onClose {
                    Button(action: onClose) { Image(systemName: "xmark").font(PlayscribeFont.headline).frame(width: 44, height: 44) }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Close")
                        .tappableFrame()
                }
            }
            Slider(value: Binding(get: { controller.current }, set: { controller.seek(to: $0) }),
                   in: 0...max(1, controller.duration))
                .accessibilityLabel("Playback position")
                .tappableFrame()
            HStack(spacing: 24) {
                Text(Self.time(controller.current)).font(PlayscribeFont.caption.monospacedDigit())
                Spacer()
                Button(action: controller.toggleMute) {
                    Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")
                .tappableFrame()
                Button(action: controller.playPause) {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill").font(PlayscribeFont.title).frame(width: 56, height: 56)
                }
                .buttonStyle(.glassProminent).foregroundStyle(PlayscribeColor.onAccent)
                .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
                .tappableFrame()
                Spacer()
                Text(Self.time(controller.duration)).font(PlayscribeFont.caption.monospacedDigit())
            }
            if duo.pose == .tabletop || duo.pose == .closed { Spacer() }
        }
        .padding(20)
        .foregroundStyle(.white)
        .background {
            if duo.pose != .tabletop {
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
            }
        }
    }

    /// Height of the 16:9 video at the top of the closed display, plus a gap.
    private var closedVideoHeight: CGFloat { duo.size.width * 9 / 16 + 8 }

    static func time(_ t: Double) -> String {
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
