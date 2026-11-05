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

    @Test func rendersEverySizeAndState() throws {
        let sample = WidgetSnapshot.sample
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
            let caught = WidgetSnapshot(rows: [], unreadCount: 0, hasGames: true)
            try write("\(s.name)-caught-up", WidgetCanvas(entry: entry(caught), family: s.family, scheme: .dark, size: s.size))
            try write("\(s.name)-no-games", WidgetCanvas(entry: entry(.empty), family: s.family, scheme: .light, size: s.size))
            shots += 2
        }
        #expect(shots == 24)
    }
}
