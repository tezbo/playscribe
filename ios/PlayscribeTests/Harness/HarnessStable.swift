import Foundation
import SwiftUI

/// HARNESS_STABLE=1: stills that are the same pixels every time the same code is rendered, so `screen-diffs.yml` can compare a
/// PR's stills with main's and list only the screens that changed (Quinn's pass bar, qa-screen-diffs-on-prs):
///   - no network: every http(s) request fails at once, so remote art always falls back to the bundled art or the title plate
///     (never "loaded on one run, not on the other");
///   - motion off: every animation in the hosted tree is dropped, so the drifting key art (ArtView) and fades jump to their end
///     state instead of being caught mid-way (SwiftUI's Reduce Motion value is read-only, so a transaction does this);
///   - an extra pause before each shot, after layout has settled, so image fades and fallbacks have finished.
/// Off by default: other harness tests and the plain stills are unchanged.
enum HarnessStable {
    static var on: Bool { ProcessInfo.processInfo.environment["HARNESS_STABLE"] == "1" }
    /// Wait after the layout settled, before the PNG (fades in the app are 0.2 s).
    static let pause: Duration = .milliseconds(600)

    nonisolated(unsafe) private static var prepared = false
    /// Turns the network off for this test process. Safe to call more than once.
    static func prepare() {
        guard on, !prepared else { return }
        prepared = true
        URLProtocol.registerClass(HarnessNoNetwork.self)
    }
}

/// Fails every http(s) request at once, as if offline. nonisolated: URLSession calls it off the main actor (the test target
/// defaults to MainActor).
nonisolated final class HarnessNoNetwork: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { ["http", "https"].contains(request.url?.scheme ?? "") }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
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
