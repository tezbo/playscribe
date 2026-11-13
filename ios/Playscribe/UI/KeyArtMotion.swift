import SwiftUI
import UIKit

// Key-art motion, the cover's second mode (s-07-keyart-motion; Iris's spec, design/keyart-motion-spec.md, 13 Nov).
// Only the art moves: a slow push-in from 1.00 to 1.08 with a drift that brings the stored focal point toward its place on the
// cover, out over 24 s and back over 24 s (ping-pong, zero velocity at both turns, so t = 0 and t = 48 s are the same frame).
// The plate, the shade and every control stay still, so the caption's contrast never changes.

/// The path, pure and frame-free so it can be tested: scale and offset at a time, for a cover of a given size.
nonisolated struct KeyArtPath: Equatable {
    static let period: Double = 48
    static let maxScale: Double = 0.08
    static let maxTravelFraction: Double = 0.04
    static let maxSpeed: Double = 2

    /// The scale's anchor, in cover points: the focal point where the crop placed it, so the push-in never moves it.
    var anchor: CGPoint
    /// The push-in at the turn (scale 1 + amplitude).
    var amplitude: Double
    /// The drift at the turn, in points.
    var drift: CGVector

    /// 0 at t = 0, 1 at t = 24 s, back to 0 at t = 48 s; cosine-eased, so its rate is zero at both turns.
    static func ease(_ t: Double) -> Double {
        let p = (t.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period) / (period / 2)
        let u = p <= 1 ? p : 2 - p
        return (1 - cos(.pi * u)) / 2
    }

    /// The ease's fastest rate, per second: d/dt of (1 - cos(pi t / 24)) / 2 at its peak.
    static let peakRate: Double = .pi / period

    func scale(at t: Double) -> Double { 1 + amplitude * Self.ease(t) }
    func offset(at t: Double) -> CGSize { let e = Self.ease(t); return CGSize(width: drift.dx * e, height: drift.dy * e) }

    /// Where a cover point is drawn at time t.
    func apply(_ p: CGPoint, at t: Double) -> CGPoint {
        let s = scale(at: t), o = offset(at: t)
        return CGPoint(x: anchor.x + (p.x - anchor.x) * s + o.width, y: anchor.y + (p.y - anchor.y) * s + o.height)
    }

    /// The fastest any point of the cover moves, in points per second (a corner, at the middle of a leg).
    func peakSpeed(in size: CGSize) -> Double {
        let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
        return corners.map { c in
            hypot((c.x - anchor.x) * amplitude + drift.dx, (c.y - anchor.y) * amplitude + drift.dy)
        }.max()! * Self.peakRate
    }

    /// The clamped path for a cover. `focal` is the focal point where the still crop put it, `target` where the cover wants it
    /// (centre, or the top quarter at accessibility sizes), `maxFocalY` the lowest the focal point may sit (half the height at
    /// accessibility sizes). Every limit holds at every moment, because every quantity moves with the same ease from zero.
    static func make(size: CGSize, focal: CGPoint, target: CGPoint, maxFocalY: Double) -> KeyArtPath {
        guard size.width > 0, size.height > 0 else { return KeyArtPath(anchor: .zero, amplitude: 0, drift: .zero) }
        let a = CGPoint(x: min(max(focal.x, 0), size.width), y: min(max(focal.y, 0), size.height))
        var amp = maxScale
        // Toward the target, at most 4% of the cover's width.
        var d = CGVector(dx: target.x - a.x, dy: target.y - a.y)
        let travel = maxTravelFraction * size.width
        let len = hypot(d.dx, d.dy)
        if len > travel { d = CGVector(dx: d.dx * travel / len, dy: d.dy * travel / len) }
        // The focal point stays inside the cover, and above maxFocalY.
        d.dx = min(max(d.dx, -a.x), size.width - a.x)
        d.dy = min(max(d.dy, -a.y), max(0, min(size.height, maxFocalY) - a.y))
        // The art always covers the cover: a drift never opens an edge the push-in has not grown past.
        func coverClamp(_ d: CGVector, _ amp: Double) -> CGVector {
            CGVector(dx: min(max(d.dx, -(size.width - a.x) * amp), a.x * amp),
                     dy: min(max(d.dy, -(size.height - a.y) * amp), a.y * amp))
        }
        d = coverClamp(d, amp)
        // Speed cap: scale the whole path down until no point moves faster than 2 pt/s.
        var path = KeyArtPath(anchor: a, amplitude: amp, drift: d)
        let speed = path.peakSpeed(in: size)
        if speed > maxSpeed {
            let k = maxSpeed / speed
            amp *= k
            d = CGVector(dx: d.dx * k, dy: d.dy * k)
            path = KeyArtPath(anchor: a, amplitude: amp, drift: d)
        }
        return path
    }
}

/// Art that fails the brightness and detail check stays still (the murky Wukong key art; Iris: never animate bad art).
enum KeyArtQuality {
    @MainActor private static var cache: [String: Bool] = [:]

    /// True when a 16 x 16 thumbnail of the art is too dark (mean luminance under 8%) or too flat (its spread under 6%).
    static func isMurky(mean: Double, spread: Double) -> Bool { mean < 0.08 || spread < 0.06 }

    @MainActor static func isMurky(asset: String) -> Bool {
        if let hit = cache[asset] { return hit }
        let result = UIImage(named: asset).flatMap(stats).map { isMurky(mean: $0.mean, spread: $0.spread) } ?? true
        cache[asset] = result
        return result
    }

    static func stats(_ image: UIImage) -> (mean: Double, spread: Double)? {
        guard let cg = image.cgImage else { return nil }
        let side = 16
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var lum: [Double] = []
        for i in stride(from: 0, to: px.count, by: 4) {
            lum.append((0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])) / 255)
        }
        let mean = lum.reduce(0, +) / Double(lum.count)
        let spread = (lum.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lum.count)).squareRoot()
        return (mean, spread)
    }
}

/// The cover's art, moving when Key-art motion is on. Transform only (scale and offset of the drawn art), so nothing re-lays
/// out or re-decodes; 30 frames a second. It pauses, without a jump on resume, while the app is not active, while the page is
/// off screen and in Low Power Mode. `-qaMotionTime <seconds>` freezes the clock at that time for stills.
struct KeyArtMotionArt: View {
    var asset: String?
    var game: CatalogGame
    var focus: CoverFocus
    var focusTargetY: Double
    var maxFocalY: Double
    var moving: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Time already played, and when the current run started.
    @State private var played: Double = 0
    @State private var runStart: Date?

    static var frozenTime: Double? {
        #if INTERNAL
        let v = UserDefaults.standard.object(forKey: "qaMotionTime")
        return (v as? Double) ?? (v as? String).flatMap(Double.init)
        #else
        return nil
        #endif
    }

    private var running: Bool { moving && Self.frozenTime == nil && onScreen && scenePhase == .active && !lowPower }

    var body: some View {
        GeometryReader { geo in
            let path = self.path(geo.size)
            Group {
                if running {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                        art(geo.size, path: path, t: played + (runStart.map { ctx.date.timeIntervalSince($0) } ?? 0))
                    }
                } else {
                    art(geo.size, path: path, t: moving ? (Self.frozenTime ?? played) : 0)
                }
            }
        }
        .clipped()
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: running, initial: true) { _, now in
            if now { runStart = .now } else if let start = runStart { played += Date.now.timeIntervalSince(start); runStart = nil }
        }
    }

    private func art(_ size: CGSize, path: KeyArtPath, t: Double) -> some View {
        let s = path.scale(at: t), o = path.offset(at: t)
        return ArtView(asset: asset, game: game, focus: focus, focusTargetY: focusTargetY)
            .frame(width: size.width, height: size.height)
            .scaleEffect(s, anchor: UnitPoint(x: path.anchor.x / max(size.width, 1), y: path.anchor.y / max(size.height, 1)))
            .offset(o)
    }

    private func path(_ size: CGSize) -> KeyArtPath {
        let natural = asset.flatMap { UIImage(named: $0)?.size } ?? CGSize(width: 1920, height: 1080)
        let r = FocalCrop.place(image: natural, in: size, focus: focus, targetY: focusTargetY)
        let fx = min(max(focus.x, 0), 1), fy = min(max(focus.y, 0), 1)
        let focal = CGPoint(x: r.minX + fx * r.width, y: r.minY + fy * r.height)
        return KeyArtPath.make(size: size, focal: focal, target: CGPoint(x: size.width / 2, y: size.height * focusTargetY),
                               maxFocalY: size.height * maxFocalY)
    }
}
