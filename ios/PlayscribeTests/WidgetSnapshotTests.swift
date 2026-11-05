import SwiftUI
import Testing
import UIKit
import WidgetKit
@testable import Playscribe

/// Renders the Home Screen widget at Small, Medium and Large in Light, Dark and Tinted (an approximation: grayscale
/// multiplied by the accent), plus caught up, no games and a light-cover fixture, and writes PNGs to a dump
/// directory the gate can collect (J-15). Set WIDGET_SNAPSHOT_DIR to choose it; the default is the temp directory.
@MainActor
struct WidgetSnapshotTests {
    private static let sizes: [(name: String, family: WidgetFamily, size: CGSize)] = [
        ("small", .systemSmall, CGSize(width: 158, height: 158)),
        ("medium", .systemMedium, CGSize(width: 338, height: 158)),
        ("large", .systemLarge, CGSize(width: 338, height: 354)),
    ]

    private var dumpDir: URL {
        let base = ProcessInfo.processInfo.environment["WIDGET_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
            ?? URL.temporaryDirectory.appending(path: "widget-snapshots")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// A flat cover fixture: `light` is near white (the worst case for white text), otherwise deep blue.
    private func fixtureCover(light: Bool) -> UIImage {
        let size = CGSize(width: 360, height: 360)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            (light ? UIColor(white: 0.97, alpha: 1) : UIColor(red: 0.08, green: 0.12, blue: 0.32, alpha: 1)).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            (light ? UIColor(white: 0.88, alpha: 1) : UIColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1)).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 180, y: 40, width: 220, height: 220))
        }
    }

    private func entry(_ snap: WidgetSnapshot) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: snap) }

    @discardableResult
    private func write(_ name: String, _ view: some View) throws -> CGSize {
        let r = ImageRenderer(content: view)
        r.scale = 2
        let img = try #require(r.uiImage, "\(name) rendered")
        let png = try #require(img.pngData())
        try png.write(to: dumpDir.appending(path: "widget-\(name).png"), options: .atomic)
        return img.size
    }

    /// The sample with dates inside the 72 h window, so the New chip and "1 new update" show.
    private var fresh: WidgetSnapshot {
        var snap = WidgetSnapshot.sample
        for i in snap.rows.indices { snap.rows[i].date = Date.now.addingTimeInterval(-Double(i + 1) * 7200) }
        return snap
    }

    private func luminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Double {
        func lin(_ c: CGFloat) -> Double { let v = Double(c); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Contrast of white text against the rendered pixel at (x, y) as fractions of the image.
    private func whiteContrast(_ img: UIImage, x: CGFloat, y: CGFloat) throws -> Double {
        let cg = try #require(img.cgImage)
        let px = Int(CGFloat(cg.width) * x), py = Int(CGFloat(cg.height) * y)
        var rgba = [UInt8](repeating: 0, count: 4)
        let ctx = try #require(CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: -px, y: -(cg.height - 1 - py), width: cg.width, height: cg.height))
        let l = luminance(CGFloat(rgba[0]) / 255, CGFloat(rgba[1]) / 255, CGFloat(rgba[2]) / 255)
        return 1.05 / (l + 0.05)
    }

    @Test func rendersEverySizeAndState() throws {
        let sample = fresh
        let ids = sample.rows.map(\.releaseID)
        let dark = Dictionary(uniqueKeysWithValues: ids.map { ($0, fixtureCover(light: false)) })
        let light = Dictionary(uniqueKeysWithValues: ids.map { ($0, fixtureCover(light: true)) })
        var shots = 0
        for s in Self.sizes {
            for (mode, scheme, tinted) in [("light", ColorScheme.light, false), ("dark", .dark, false), ("tinted", .dark, true)] {
                let size = try write("\(s.name)-\(mode)", WidgetCanvas(entry: entry(sample), family: s.family, scheme: scheme,
                                                                        size: s.size, covers: dark, tinted: tinted))
                #expect(size == s.size, "\(s.name)-\(mode) renders at the tile size")
                try write("\(s.name)-\(mode)-lightcover", WidgetCanvas(entry: entry(sample), family: s.family, scheme: scheme,
                                                                         size: s.size, covers: light, tinted: tinted))
                shots += 2
            }
            // 72 h rule: the same sample with its October dates must show no New chip and no "new update" heading.
            try write("\(s.name)-stale-72h", WidgetCanvas(entry: entry(.sample), family: s.family, scheme: .dark, size: s.size, covers: dark))
            let caught = WidgetSnapshot(rows: [], unreadCount: 0, hasGames: true)
            try write("\(s.name)-caught-up", WidgetCanvas(entry: entry(caught), family: s.family, scheme: .dark, size: s.size))
            try write("\(s.name)-no-games", WidgetCanvas(entry: entry(.empty), family: s.family, scheme: .light, size: s.size))
            shots += 3
        }
        #expect(shots == 30)
    }

    @Test func staleUnreadIsNotNew() {
        let stale = WidgetSnapshot.sample.freshened(at: .now)
        #expect(stale.rows.allSatisfy { !$0.unread } && stale.unreadCount == 0)
        let keep = fresh.freshened(at: .now)
        #expect(keep.rows[0].unread && keep.unreadCount == 1)
    }

    /// Iris/Quinn: white text on the scrim holds 4.5:1 over the lightest possible cover. Writes the ratios beside the stills.
    @Test func scrimHoldsContrastOnWhiteCover() throws {
        let white = Dictionary(uniqueKeysWithValues: fresh.rows.map { ($0.releaseID, UIImage.solid(.white)) })
        var report = ""
        for (name, family, size, y) in [("small", WidgetFamily.systemSmall, CGSize(width: 158, height: 158), CGFloat(0.42)),
                                         ("medium", .systemMedium, CGSize(width: 338, height: 158), 0.42)] {
            let r = ImageRenderer(content: WidgetCanvas(entry: entry(fresh), family: family, scheme: .light, size: size, covers: white))
            r.scale = 2
            let ratio = try whiteContrast(try #require(r.uiImage), x: name == "medium" ? 0.45 : 0.9, y: y)
            report += "\(name) at \(Int(y * 100))% of height: \(String(format: "%.2f", ratio)):1\n"
            #expect(ratio >= 4.5, "\(name) scrim holds 4.5:1 on a white cover (\(ratio))")
        }
        // Large: sample inside the hero band where its text sits (45% down the band).
        let size = Self.sizes[2].size
        let band = WidgetLayout.largeHeroFraction(rowCount: 5)
        let r = ImageRenderer(content: WidgetCanvas(entry: entry(fresh), family: .systemLarge, scheme: .light, size: size, covers: white))
        r.scale = 2
        let ratio = try whiteContrast(try #require(r.uiImage), x: 0.95, y: band * 0.45)
        report += "large hero at 45% of band: \(String(format: "%.2f", ratio)):1\n"
        #expect(ratio >= 4.5, "large scrim holds 4.5:1 on a white cover (\(ratio))")
        try report.write(to: dumpDir.appending(path: "widget-contrast.txt"), atomically: true, encoding: .utf8)
    }

    /// Real bundled art from the demo library (Dawnwalker, CONTROL and the rest), Light and Dark, all sizes.
    @Test func rendersWithRealArt() throws {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "widget-\(UUID().uuidString).json"))
        m.resetDemo()
        var covers: [String: UIImage] = [:]
        let rows: [WidgetSnapshot.Row] = m.latestDeck.compactMap { c in
            guard let r = c.release else { return nil }
            if let asset = c.game.keyArtAsset, let img = UIImage(named: asset) { covers[r.id] = img }
            return .init(gameID: c.game.id, game: c.game.name, releaseID: r.id, update: r.displayName,
                         date: Date.now.addingTimeInterval(-3 * 3600), unread: c.unread, chip: r.versionChip)
        }.prefix(WidgetLayout.largeRowLimit).map { $0 }
        let snap = WidgetSnapshot(rows: rows, unreadCount: rows.filter(\.unread).count, hasGames: true)
        #expect(!rows.isEmpty && !covers.isEmpty, "demo has bundled art")
        for s in Self.sizes {
            for (mode, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                try write("realart-\(s.name)-\(mode)", WidgetCanvas(entry: entry(snap), family: s.family, scheme: scheme,
                                                                    size: s.size, covers: covers))
            }
        }
    }
}

private extension UIImage {
    static func solid(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
    }
}
