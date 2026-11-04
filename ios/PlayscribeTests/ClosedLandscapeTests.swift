import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Playscribe

/// J-5 in Closed landscape. The simulator cannot drive the outer panel sideways (it stays 466x678),
/// so these tests host the real views in a 678x466 window with a Closed DuoContext and the compact
/// size class, and read the frames the app reports to the fold audit (`tappableFrame`).
///
/// What this proves: the layout rules at that size, in the app's own geometry. What it cannot prove:
/// the OS's safe areas, the real reserved regions and device rendering. Those stay on the physical
/// Duo (Terry's TestFlight checklist).
@MainActor
struct ClosedLandscapeTests {
    static let size = CGSize(width: 678, height: 466)

    private final class FrameBox: @unchecked Sendable { var frames: [CGRect] = [] }

    private func model() -> AppModel {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "cl-\(UUID().uuidString).json"))
        m.resetDemo()
        return m
    }

    /// Hosts `view` at the Closed-landscape size and returns the frames it reported.
    private func reportedFrames<V: View>(_ view: V, model: AppModel, size: CGSize = ClosedLandscapeTests.size) async throws -> [CGRect] {
        let wasOn = FoldAuditSwitch.enabled
        FoldAuditSwitch.enabled = true
        defer { FoldAuditSwitch.enabled = wasOn }
        let box = FrameBox()
        let ctx = DuoContext(size: size)
        let root = NavigationStack { view }
            .environment(model)
            .environment(\.duo, ctx)
            .environment(\.horizontalSizeClass, .compact)
            .preferredColorScheme(.dark)
            .frame(width: size.width, height: size.height)
            .onPreferenceChange(TappableFrameKey.self) { box.frames = $0 }
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(900))
        host.view.layoutIfNeeded()
        window.isHidden = true
        return box.frames
    }

    private var bounds: CGRect { CGRect(origin: .zero, size: Self.size) }

    @Test("J-5: Library covers are 3:4, equal, in bounds and never overlap at the 678 pt Closed-landscape width")
    func libraryCovers() async throws {
        // At 466 pt high the first tile row sits below the Continue hero and is clipped by the scroll
        // view (the audit only reports the visible part), so the window is tall here: the width
        // is what decides tile size, 3:4 and overlap. Bounds are checked at the real size below.
        let tall = CGSize(width: Self.size.width, height: 1600)
        let frames = try await reportedFrames(LibraryView(), model: model(), size: tall)
        // Covers: reported tile frames are 3:4 portrait boxes.
        let covers = frames.filter { $0.width > 40 && abs($0.width / $0.height - 0.75) < 0.05 }
        #expect(covers.count >= 3, "at least one row of covers is reported, got \(covers.count)")
        if let first = covers.first {
            for c in covers {
                #expect(abs(c.width - first.width) <= 2, "equal widths: \(c) vs \(first)")
                #expect(abs(c.height / c.width - 4.0 / 3.0) <= 0.08, "3:4 cover: \(c)")
            }
        }
        for (i, a) in covers.enumerated() {
            for b in covers[(i + 1)...] {
                #expect(!a.insetBy(dx: 0.5, dy: 0.5).intersects(b), "covers overlap: \(a) and \(b)")
            }
        }
        // Closed has no division and no occlusion: nothing may leave the window.
        for f in frames where f.width > 1 && f.height > 1 {
            #expect(f.minX >= -1 && f.maxX <= bounds.maxX + 1, "frame leaves the window sideways: \(f)")
        }
    }

    @Test("J-5: Library controls stay inside the 678x466 window")
    func libraryBounds() async throws {
        let frames = try await reportedFrames(LibraryView(), model: model())
        #expect(!frames.isEmpty, "the Library reports controls")
        for f in frames where f.width > 1 && f.height > 1 {
            #expect(f.minX >= -1 && f.maxX <= bounds.maxX + 1, "frame leaves the window sideways: \(f)")
        }
    }

    @Test("J-5: release page controls stay inside the window at 678x466")
    func releasePage() async throws {
        let m = model()
        let frames = try await reportedFrames(ReleaseDetailView(gameID: "dawnwalker", releaseID: "dawnwalker@1.1"), model: m)
        #expect(!frames.isEmpty, "the release page reports controls")
        for f in frames where f.width > 1 && f.height > 1 {
            #expect(f.minX >= -1 && f.maxX <= bounds.maxX + 1, "release control leaves the window: \(f)")
        }
    }

    @Test("J-5: Settings controls stay inside the window at 678x466")
    func settings() async throws {
        let frames = try await reportedFrames(SettingsView(), model: model())
        for f in frames where f.width > 1 && f.height > 1 {
            #expect(f.minX >= -1 && f.maxX <= bounds.maxX + 1, "settings control leaves the window: \(f)")
        }
    }
}
