import SwiftUI
import UIKit
import WebKit

/// Reflection mode (R-11): a faint, blurred mirror of the video under the Tabletop controls. Drawn by the app; no
/// system API exists for one. One view for both players (update videos and game trailers), so the height, fade and
/// opacity are the same in every state (Iris, 12 Nov).
///
/// It starts on the still (the bundled poster, or the video's own thumbnail) and crossfades to live frames only when a
/// frame of the player comes back with a picture in it. WebKit often leaves a playing video out of a web view snapshot,
/// so the live frame can be all black; then the mirror stays on the still instead of going black (Terry, 12 Nov:
/// "Video reflections definitely don't work"). View only: it never takes touches (Tabletop rule).
struct VideoReflection: View {
    static let key = "reflectionMode"
    /// On unless the person turns it off (Terry, 2026-11-06). The Settings toggle reads the same value.
    static let defaultOn = true

    /// Peak strength of the mirror. 0.35 measured 20 to 30 of 255 on the Tabletop still, too faint to see (Quinn, 12 Nov).
    static let opacity = 0.7

    enum Mode: Equatable { case off, still, live }

    /// Reduce Transparency turns the mirror off. Reduce Motion keeps it on the still (G-9: nothing moves; Iris, 12 Nov).
    static func mode(setting: Bool, reduceMotion: Bool, reduceTransparency: Bool) -> Mode {
        guard setting, !reduceTransparency else { return .off }
        return reduceMotion ? .still : .live
    }

    /// The still, as an address: a bundled poster wins, else the video's thumbnail (the same host the game page's
    /// video tiles already load from).
    static func thumbnailURL(_ youtubeID: String) -> URL? { URL(string: "https://i.ytimg.com/vi/\(youtubeID)/hqdefault.jpg") }

    /// QA (INTERNAL, `-qaBlankFrame YES`): every live snapshot comes back all black, as WebKit often gives for a playing
    /// video, so the fallback to the still can be shot. Ignored in a distribution build.
    static var forceBlankFrame: Bool { BuildChannel.showsInternalTools && UserDefaults.standard.bool(forKey: "qaBlankFrame") }

    /// Which picture the mirror shows: a live frame only when it has a picture in it, never a black one.
    static func pick(live: UIImage?, still: UIImage?) -> UIImage? {
        if let live, !isBlank(live) { return live }
        return still
    }

    /// True when the frame is (nearly) all black: the mean brightness of an 8 x 8 thumbnail of it is under 4%.
    static func isBlank(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let side = 8
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return true }
        var sum = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            sum += 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
        }
        return sum / Double(side * side) / 255 < 0.04
    }

    var controller: YouTubeController
    var mode: Mode
    var posterAsset: String?
    var youtubeID: String
    @State private var live: UIImage?
    @State private var thumbnail: UIImage?

    private var still: UIImage? { posterAsset.flatMap { UIImage(named: $0) } ?? thumbnail }
    private var shown: UIImage? { mode == .live ? Self.pick(live: live, still: still) : still }

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image = shown {
                    Image(uiImage: image).resizable().aspectRatio(16 / 9, contentMode: .fill)
                        .id(image)
                        .transition(.opacity)
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: shown)
            .scaleEffect(x: 1, y: -1)
            .blur(radius: 10)
            .saturation(1.2)
            .opacity(Self.opacity)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.3), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: youtubeID) {
                guard posterAsset.flatMap({ UIImage(named: $0) }) == nil, thumbnail == nil, let url = Self.thumbnailURL(youtubeID),
                      let loaded = try? await URLSession.shared.data(from: url) else { return }
                thumbnail = UIImage(data: loaded.0)
            }
            .task(id: mode == .live && controller.isPlaying) {
                guard mode == .live, controller.isPlaying else { return }
                while !Task.isCancelled {
                    let cfg = WKSnapshotConfiguration()
                    cfg.snapshotWidth = 320
                    if let img = try? await controller.webView.takeSnapshot(configuration: cfg) {
                        let frame = Self.forceBlankFrame ? UIGraphicsImageRenderer(size: img.size).image { c in UIColor.black.setFill(); c.fill(CGRect(origin: .zero, size: img.size)) } : img
                        if !Self.isBlank(frame) { live = frame }
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
    }
}
