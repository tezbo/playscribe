import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// PNG stills from the fold harness, for people who judge app-owned layout (wraps, truncation, overlap, chip layout) without the
/// Mac. Off unless `HARNESS_PNG_DIR` is set, so a normal test run does nothing here. Written by `harness-stills.yml`.
///   HARNESS_PNG_DIR    folder for the PNGs, named <pose>-<size>.png
///   HARNESS_POSES      comma list of pose ids (default: all in the catalog)
///   HARNESS_SIZES      comma list of std, ax3, ax5 (default: all three)
///   HARNESS_ROUTE      a playscribe:// host and path to open first, e.g. game/dawnwalker (default: the Library)
///   HARNESS_SCREENS    comma list of named screens for a whole matrix in one job (see `screens`); overrides ROUTE and VIEW
///   HARNESS_SPLIT=1    lay Book and Tabletop pages out by the injected division (stand-in, triage only); without it the Book PNG's
///                      left page is clipped at x 0 and reads as a false alarm (Quinn, matrix 7fb7d89)
/// Beside every PNG: one index.txt line (pose, live pose, safe area, fold, occlusions, split, settled) and <file>-frames.txt.
@MainActor
struct HarnessStillsTests {
    static let sizes: [(String, UIContentSizeCategory)] = [("std", .large), ("ax3", .accessibilityExtraLarge), ("ax5", .accessibilityExtraExtraExtraLarge)]

    /// HARNESS_SCREENS: a comma list of named screens, so one request renders a whole matrix (poses x sizes x screens) in one job
    /// (r052-harness-png-matrix). Files are named <screen>-<pose>-<size>.png and every one is listed in index.txt.
    ///   library   the Library          game      the KCD II game page (game/kcd2)     updates   the Updates tab (many-updates/updates)
    ///   settings  SettingsView hosted directly (a system sheet is not in the capture); HARNESS_TALL scales it
    ///   upcoming  Library > Upcoming (library/upcoming)
    /// Unset: the older single-request behaviour below (HARNESS_ROUTE / HARNESS_VIEW, files named <pose>-<size>.png).
    static let screens: [String: (route: String?, view: String?)] = [
        "library": (nil, nil), "game": ("game/kcd2", nil), "updates": ("many-updates/updates", nil),
        "settings": (nil, "settings"), "upcoming": ("library/upcoming", nil),
    ]

    @Test(arguments: ["closed", "closedLandscape", "open", "openPortrait", "book", "tabletop"], ["std", "ax3", "ax5"])
    func writeStill(_ id: String, _ size: String) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["HARNESS_PNG_DIR"], !dir.isEmpty else { return }
        func wanted(_ key: String, _ value: String) -> Bool {
            guard let list = env[key], !list.isEmpty else { return true }
            return list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(value)
        }
        guard wanted("HARNESS_POSES", id), wanted("HARNESS_SIZES", size) else { return }
        let category = try #require(Self.sizes.first { $0.0 == size }?.1)
        let tall = Double(env["HARNESS_TALL"] ?? "") ?? 1
        if let list = env["HARNESS_SCREENS"], !list.isEmpty {
            for name in list.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !name.isEmpty {
                guard let screen = Self.screens[name] else {
                    // A typo must show in the artifact itself, not only in the log (Quinn, #457 review).
                    let line = "missing: \(name) is not a known screen (known: \(Self.screens.keys.sorted().joined(separator: ","))); pose \(id) size \(size)"
                    print("harness error: \(line)")
                    Self.append(line, toIndexIn: dir)
                    continue
                }
                try await still(id, size, category, route: screen.route, view: screen.view, tall: tall, dir: dir, file: "\(name)-\(id)-\(size)")
            }
            return
        }
        try await still(id, size, category, route: env["HARNESS_ROUTE"], view: env["HARNESS_VIEW"], tall: tall, dir: dir,
                        file: env["HARNESS_VIEW"].flatMap { $0.isEmpty ? nil : "\($0)-\(id)-\(size)" } ?? "\(id)-\(size)")
    }

    private func still(_ id: String, _ size: String, _ category: UIContentSizeCategory, route: String?, view: String?, tall: Double,
                       dir: String, file: String) async throws {
        let model = FoldHost.demoModel()
        if let route, !route.isEmpty, let url = URL(string: "playscribe://\(route)") { model.handle(url: url) }
        // Whether a QA route (one-update, many-updates, ...) took effect: it must show in the log, not only in the still.
        print("harness route: \(route ?? "none") qaRoute \(model.qaRoute ?? "nil") games \(model.data.collection.count) hero \(model.continueItem?.release.id ?? "none")")
        // A view (settings): host that screen's view directly (the app presents it as a system sheet in Closed, which the capture of
        // the hosting view does not include). HARNESS_TALL scales the height so its scroll content shows.
        let rendered: Rendered
        if let which = view, !which.isEmpty {
            switch which {
            case "settings":
                rendered = try #require(await FoldHost.renderView(SettingsView(), pose: HarnessPose.named(id), type: category, model: model, heightScale: CGFloat(tall)),
                                        "settings did not render")
            default: throw HarnessStillError.unknownView(which)
            }
        } else {
            var pose = HarnessPose.named(id)
            // HARNESS_TALL=<n>: host the pose in a window n times taller so a scrolling screen (the Library's deck sits below the
            // alerts and PS Plus cards) shows more than its first screen. Advisory only: the real pose is not this tall.
            if tall > 1, !pose.landscape { pose.container.height *= CGFloat(tall) }
            rendered = try #require(await FoldHost.render(pose, type: category, model: model), "\(id) did not render")
        }
        defer { FoldHost.dispose(rendered) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try #require(FoldHost.png(rendered))
        try data.write(to: URL(fileURLWithPath: dir).appending(path: "\(file).png"))
        // One index line per still. The PNG is the pose's window (container plus safe area) at 1 px per pt. The pose label, the fold
        // (division) and the occlusions are the catalog's, in container points, so a Book or Tabletop PNG can be read against its
        // band without the Mac (Iris, #457 review); "live" is the pose the app itself derived from the injected regions.
        let p = rendered.pose
        let split = ProcessInfo.processInfo.environment["HARNESS_SPLIT"] == "1"
        let line = "\(file).png \(Int(p.windowSize.width))x\(Int(p.windowSize.height)) pose \(p.id) expected \(p.expected) live \(rendered.livePose)"
            + " safe \(Int(p.safeArea.top)),\(Int(p.safeArea.left)),\(Int(p.safeArea.bottom)),\(Int(p.safeArea.right))"
            + " fold \(p.division.map(Self.rect) ?? "none") occlusions \(p.occlusions.isEmpty ? "none" : p.occlusions.map(Self.rect).joined(separator: ";"))"
            + " split \(split ? 1 : 0) settled \(rendered.settled) after \(rendered.passes) passes route \(route ?? "-") view \(view ?? "-")"
        print("harness still: \(line)")
        Self.append(line, toIndexIn: dir)
        // A frame dump beside the PNG, like the Mac's tile dumps: every tappable frame the app reports (named ones by their
        // accessibility identifier), in container points, so hinge keep-out and the Tabletop above-fold rule (TB-1, TT-0) can be read
        // from the artifact. The container's origin sits at safe-area left,top in the PNG.
        var dump = ["# \(file): tappable frames in container points (x,y wxh); add safe left \(Int(p.safeArea.left)) top \(Int(p.safeArea.top)) for PNG px",
                    "# fold \(p.division.map(Self.rect) ?? "none"); frames the harness does not capture (Updates rows, system sheets) are absent, see docs/fold-harness.md"]
        dump += rendered.named.sorted { $0.key < $1.key }.map { "\($0.key) \(Self.rect($0.value))" }
        dump += rendered.frames.sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }.map { "frame \(Self.rect($0))" }
        try (dump.joined(separator: "\n") + "\n").write(to: URL(fileURLWithPath: dir).appending(path: "\(file)-frames.txt"), atomically: true, encoding: .utf8)
    }

    enum HarnessStillError: Error { case unknownView(String) }

    static func rect(_ r: CGRect) -> String { "\(Int(r.minX.rounded())),\(Int(r.minY.rounded())) \(Int(r.width.rounded()))x\(Int(r.height.rounded()))" }

    /// Appends one line to `<dir>/index.txt`, creating the file and folder when missing.
    static func append(_ line: String, toIndexIn dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let index = dir + "/index.txt"
        if !FileManager.default.fileExists(atPath: index) { FileManager.default.createFile(atPath: index, contents: nil) }
        guard let handle = FileHandle(forWritingAtPath: index) else { return }
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
        try? handle.close()
    }

    /// #292 hypothesis, reported and not asserted: the AX5 Tabletop layout never settles because the deck stage measures itself and
    /// feeds that into its own padding. If so, `settled` is false here. Becomes an assertion once #292's fix is on main.
    @Test func tabletopDeckSettlesAtAX5() async throws {
        let r = try #require(await FoldHost.render(HarnessPose.named("tabletop"), type: .accessibilityExtraExtraExtraLarge))
        defer { FoldHost.dispose(r) }
        print("harness error: [info, not asserted] tabletop AX5 settled \(r.settled) after \(r.passes) passes (#292)")
    }
}
