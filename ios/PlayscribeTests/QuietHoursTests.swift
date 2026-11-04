import Testing
import Foundation
@testable import Playscribe

struct QuietHoursTests {
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))!
    }

    @Test func crossesMidnight() {
        let q = QuietHours()
        #expect(q.contains(at(23)) && q.contains(at(3)) && q.contains(at(22)))
        #expect(!q.contains(at(8)) && !q.contains(at(12)) && !q.contains(at(21, 59)))
    }

    @Test func sameDayRangeAndEmpty() {
        #expect(QuietHours(from: 13 * 60, until: 15 * 60).contains(at(14)))
        #expect(!QuietHours(from: 13 * 60, until: 15 * 60).contains(at(16)))
        #expect(!QuietHours(from: 600, until: 600).contains(at(10)))
    }

    @Test func label() { #expect(QuietHours().label == "22:00 to 08:00") }
}

/// r050-quiet-hours-push: what the app sends the relay.
struct QuietWindowTests {
    @Test func windowCarriesMinutesAndZone() {
        let w = PushRegistrar.quietWindow(QuietHours(from: 22 * 60, until: 8 * 60), timeZone: TimeZone(identifier: "Europe/London")!)
        #expect(w == PushRegistrar.QuietWindow(from: 1320, until: 480, timeZone: "Europe/London"))
    }

    @Test func offOrEmptyWindowSendsNothing() {
        #expect(PushRegistrar.quietWindow(nil) == nil)
        #expect(PushRegistrar.quietWindow(QuietHours(from: 600, until: 600)) == nil)
    }
}
