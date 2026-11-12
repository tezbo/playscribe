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

    /// Peak strength 40% at the video's bottom edge, fading out over 120 pt (the visibility bar, Iris and Quinn, 12 Nov).
    static let opacity = 0.4
    static let height: CGFloat = 120

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
    static func isBlank(_ image: UIImage) -> Bool { meanBrightness(image) < 0.04 }

    /// Mean luminance, 0 to 1, of an 8 x 8 thumbnail of the image (0 when it cannot be drawn).
    static func meanBrightness(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
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
        guard drawn else { return 0 }
        var sum = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            sum += 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
        }
        return sum / Double(side * side) / 255
    }

    /// QA (INTERNAL, `-qaMirrorRaw YES`): the mirror at full strength, no fade, no plate behind text, so a still shows what the
    /// picture is. With it, each snapshot logs `mirror-probe` lines (mean brightness of the live frame and the still).
    static var raw: Bool { BuildChannel.showsInternalTools && UserDefaults.standard.bool(forKey: "qaMirrorRaw") }

    /// QA (INTERNAL, `-qaMirrorFixture YES`): the mirror is fed a generated bright "playing" frame every 250 ms (colour bars
    /// that shift hue, mean brightness about 0.6), as if the video were playing and every snapshot had a picture in it. The
    /// simulator's YouTube embed often never starts, so this measures the live path (crossfade, band, fade, plate) without it.
    static var fixture: Bool { BuildChannel.showsInternalTools && UserDefaults.standard.bool(forKey: "qaMirrorFixture") }

    /// The fixture frame for tick `n`: eight vertical pastel bars (saturation 0.55, brightness 0.95), hues rotated by `n`.
    static func fixtureFrame(_ n: Int, size: CGSize = CGSize(width: 320, height: 180)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { c in
            let bars = 8
            for i in 0..<bars {
                let hue = (CGFloat((i + n) % bars) / CGFloat(bars))
                UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1).setFill()
                c.fill(CGRect(x: size.width * CGFloat(i) / CGFloat(bars), y: 0, width: size.width / CGFloat(bars) + 1, height: size.height))
            }
        }
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
        // Flush under the video's bottom edge and 120 pt tall: the picture's last rows, mirrored, so the video seems to
        // stand on a glossy surface (Iris and Quinn, 12 Nov: required in Tabletop, Closed and Book).
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .overlay {
                // The picture is as wide as the column and 16:9, its last rows land in the 120 pt window (the view is flipped
                // below, so they sit at the video's bottom edge). Fitting it inside the window instead drew a small centred
                // thumbnail, which is why the band measured 1 to 6% (12 Nov).
                GeometryReader { g in
                    if let image = shown {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: g.size.width, height: g.size.width * 9 / 16)
                            .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
                            .clipped()
                            .id(image)
                            .transition(.opacity)
                    }
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: shown)
            .scaleEffect(x: 1, y: -1)
            .blur(radius: Self.raw ? 0 : 6)
            .opacity(Self.raw ? 1 : Self.opacity)
            .mask(Self.raw ? LinearGradient(colors: [.black], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: youtubeID) {
                guard posterAsset.flatMap({ UIImage(named: $0) }) == nil, thumbnail == nil, let url = Self.thumbnailURL(youtubeID),
                      let loaded = try? await URLSession.shared.data(from: url) else { return }
                thumbnail = UIImage(data: loaded.0)
            }
            .task(id: mode == .live && Self.fixture) {
                guard mode == .live, Self.fixture else { return }
                var n = 0
                // Let the still show first, so the stills can show the crossfade from it.
                try? await Task.sleep(for: .seconds(2))
                while !Task.isCancelled {
                    let frame = Self.fixtureFrame(n)
                    NSLog("mirror-probe fixture=1 live=%.3f still=%@ size=%dx%d", Self.meanBrightness(frame),
                          still.map { String(format: "%.3f", Self.meanBrightness($0)) } ?? "none", Int(frame.size.width), Int(frame.size.height))
                    if !Self.isBlank(frame) { live = frame }
                    n += 1
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            .task(id: mode == .live && controller.isPlaying && !Self.fixture) {
                guard mode == .live, controller.isPlaying, !Self.fixture else { return }
                while !Task.isCancelled {
                    let cfg = WKSnapshotConfiguration()
                    cfg.snapshotWidth = 320
                    if let img = try? await controller.webView.takeSnapshot(configuration: cfg) {
                        let frame = Self.forceBlankFrame ? UIGraphicsImageRenderer(size: img.size).image { c in UIColor.black.setFill(); c.fill(CGRect(origin: .zero, size: img.size)) } : img
                        if Self.raw {
                            NSLog("mirror-probe live=%.3f still=%@ size=%dx%d forcedBlank=%d", Self.meanBrightness(frame),
                                  still.map { String(format: "%.3f", Self.meanBrightness($0)) } ?? "none", Int(frame.size.width), Int(frame.size.height), Self.forceBlankFrame ? 1 : 0)
                        }
                        if !Self.isBlank(frame) { live = frame }
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
    }
}

extension View {
    /// Text that sits over the mirror (R-11, Max and Iris, 12 Nov): a soft-edged black plate at 92% behind it, so grey text keeps
    /// 4.5:1 on any frame, bright ones included. The plate adds no layout room and takes no touches.
    @ViewBuilder func overMirror(_ on: Bool) -> some View {
        if on, !VideoReflection.raw {
            background {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.92))
                    .padding(-8).blur(radius: 6).allowsHitTesting(false)
            }
        } else { self }
    }
}
