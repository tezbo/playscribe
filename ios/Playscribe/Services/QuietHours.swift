import Foundation

/// Quiet hours: minutes since midnight, a range that may cross midnight (22:00 to 08:00).
/// During the range alerts are delivered passively: no sound, no banner.
struct QuietHours: Codable, Equatable {
    var from = 22 * 60
    var until = 8 * 60

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if from == until { return false }
        return from < until ? (m >= from && m < until) : (m >= from || m < until)
    }

    static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    static func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// "22:00 to 08:00"
    var label: String { "\(Self.hm(from)) to \(Self.hm(until))" }
    static func hm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
}
