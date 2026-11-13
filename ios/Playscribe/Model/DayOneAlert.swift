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
        guard r.kind == .dayOne, let p = r.ps5, p.status == .live, p.verification == .official else { return false }
        return isUnread(r)
    }

    /// The chip on a fresh update ("New update", or "Day-one patch"); nil once read.
    func freshLabel(_ r: Release) -> String? {
        guard isUnread(r) else { return nil }
        return isDayOneAlert(r) ? FreshCopy.dayOne : FreshCopy.newUpdate
    }

    /// The one line under the update's headline on the game page (its Updates chapter) while a day-one patch is unread, or
    /// on the visit that read it: opening the page reads it before the page appears (R-6a), so that visit still shows it.
    func dayOneNote(_ r: Release) -> String? {
        isDayOneAlert(r) || dayOneVisit == r.id ? FreshCopy.dayOneNote : nil
    }
}
