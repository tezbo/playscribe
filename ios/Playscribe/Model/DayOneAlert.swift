import Foundation

/// r060-dayone-patch-alert-app (Iris's spec, design/dayone-alert-spec.md): an unread day-one patch says so where a fresh
/// update already shows ("Day-one patch" chip, DAY-ONE PATCH eyebrow, one line on the game page). No new screen, schema
/// or push. Only a release of kind `dayOne` whose own PS5 row is live and official counts, never one made On PS5 by a PC row.
enum FreshCopy {
    static let newUpdate = "New update"
    static let dayOne = "Day-one patch"
    static let dayOneNote = "Install this before you first play."
}

extension AppModel {
    /// Whether `r` shows as a day-one patch: unread, kind dayOne, and its PS5 row itself live and official.
    func isDayOneAlert(_ r: Release) -> Bool {
        false
    }

    /// The chip on a fresh update ("New update", or "Day-one patch"); nil once read.
    func freshLabel(_ r: Release) -> String? {
        isUnread(r) ? FreshCopy.newUpdate : nil
    }

    /// The game page's one line under the header while a day-one patch is unread.
    func dayOneNote(_ r: Release) -> String? {
        nil
    }
}
