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
@MainActor
struct HarnessStillsTests {
    static let sizes: [(String, UIContentSizeCategory)] = [("std", .large), ("ax3", .accessibilityExtraLarge), ("ax5", .accessibilityExtraExtraExtraLarge)]

    @Test(arguments: HarnessPose.catalog.map(\.id), ["std", "ax3", "ax5"])
    func writeStill(_ id: String, _ size: String) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["HARNESS_PNG_DIR"], !dir.isEmpty else { return }
        func wanted(_ key: String, _ value: String) -> Bool {
            guard let list = env[key], !list.isEmpty else { return true }
            return list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(value)
        }
        guard wanted("HARNESS_POSES", id), wanted("HARNESS_SIZES", size) else { return }
        let category = try #require(Self.sizes.first { $0.0 == size }?.1)
        let model = FoldHost.demoModel()
        if let route = env["HARNESS_ROUTE"], !route.isEmpty, let url = URL(string: "playscribe://\(route)") { model.handle(url: url) }
        let r = try #require(await FoldHost.render(HarnessPose.named(id), type: category, model: model))
        defer { FoldHost.dispose(r) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try #require(FoldHost.png(r))
        try data.write(to: URL(fileURLWithPath: dir).appending(path: "\(id)-\(size).png"))
        print("harness still: \(id)-\(size).png \(Int(r.pose.windowSize.width))x\(Int(r.pose.windowSize.height)) settled \(r.settled) after \(r.passes) passes")
    }

    /// #292 hypothesis, reported and not asserted: the AX5 Tabletop layout never settles because the deck stage measures itself and
    /// feeds that into its own padding. If so, `settled` is false here. Becomes an assertion once #292's fix is on main.
    @Test func tabletopDeckSettlesAtAX5() async throws {
        let r = try #require(await FoldHost.render(HarnessPose.named("tabletop"), type: .accessibilityExtraExtraExtraLarge))
        defer { FoldHost.dispose(r) }
        print("harness error: [info, not asserted] tabletop AX5 settled \(r.settled) after \(r.passes) passes (#292)")
    }
}
