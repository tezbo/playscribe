import Foundation
import SwiftUI

/// HARNESS_STABLE=1: stills that are the same pixels every time the same code is rendered, so `screen-diffs.yml` can compare a
/// PR's stills with main's and list only the screens that changed (Quinn's pass bar, qa-screen-diffs-on-prs):
///   - no network: not done here. A URLProtocol registered in the test process did not stop AsyncImage or TileArtLoader (the
///     first #485 run loaded IGDB art), so screen-diffs.yml blocks the art and feed hosts in the runner's /etc/hosts and remote
///     art falls back to bundled art or the title plate on both sides;
///   - motion off: every animation in the hosted tree is dropped, so the drifting key art (ArtView) and fades jump to their end
///     state instead of being caught mid-way (SwiftUI's Reduce Motion value is read-only, so a transaction does this; the
///     workflow also turns Reduce Motion on in the simulator, so ArtView's drift never starts);
///   - an extra pause before each shot, after layout has settled, so image fades and fallbacks have finished.
/// Off by default: other harness tests and the plain stills are unchanged.
enum HarnessStable {
    static var on: Bool { ProcessInfo.processInfo.environment["HARNESS_STABLE"] == "1" }
    /// Wait after the layout settled, before the PNG (fades in the app are 0.2 s).
    static let pause: Duration = .milliseconds(600)
    /// A game page marks its open update read once the body has been half on screen for 1 s (R-6, JournalView). Whether that
    /// timer had fired by the shot was a race (#485 run 5: game-book read on one side, unread with "Mark 1 read" on the other),
    /// so game routes wait past it, and again for the re-layout the read state causes.
    static func wait(route: String?) -> Duration {
        (route ?? "").hasPrefix("game") ? .milliseconds(1600) : pause
    }
}

/// No animations in stable mode; nothing otherwise.
struct HarnessStableMotion: ViewModifier {
    func body(content: Content) -> some View {
        if HarnessStable.on {
            content.transaction { t in
                t.animation = nil
                t.disablesAnimations = true
            }
        } else { content }
    }
}
