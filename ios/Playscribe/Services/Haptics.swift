import UIKit

/// Scan and Add feedback (handoff/0.5.0-scan-haptics.md). Light touches only, no sound, nothing on a loop.
/// All of it is off under Reduce Motion. `Throttle` is split out so the 400 ms rule is unit-testable.
struct HapticThrottle {
    var minGap: TimeInterval = 0.4
    private var last: Date?
    /// True (and records the time) when enough time has passed since the last allowed haptic.
    mutating func allow(at now: Date = .now) -> Bool {
        if let last, now.timeIntervalSince(last) < minGap { return false }
        last = now
        return true
    }
}

@MainActor
enum Haptics {
    private static var recognised = HapticThrottle()
    private static var enabled: Bool { !UIAccessibility.isReduceMotionEnabled }

    /// A newly recognised title in the camera: light impact, at most one per 400 ms.
    static func recognisedTitle() {
        guard enabled, recognised.allow() else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    /// Voice start and stop.
    static func voiceEdge() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    /// A match ticked or unticked in results.
    static func selection() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    private static var lastPop = Date.distantPast
    /// Add pop: light at the first tile's peak, soft for later tiles at most every 120 ms.
    static func pop(first: Bool) {
        guard enabled, Date.now.timeIntervalSince(lastPop) >= (first ? 0 : 0.12) else { return }
        lastPop = .now
        UIImpactFeedbackGenerator(style: first ? .light : .soft).impactOccurred()
    }
    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
