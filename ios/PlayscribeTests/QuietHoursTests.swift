import Testing
import Foundation
import UserNotifications
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

/// N-1: the invitation card's schedule.
struct NotificationAskTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func shows(_ status: UNAuthorizationStatus, games: Bool = true, asks: Int = 0, until: Date? = nil) -> Bool {
        NotificationAsk.shows(hasGames: games, status: status, asks: asks, snoozedUntil: until, now: now)
    }

    @Test func asksWhenUndecidedOrDeniedAndAGameIsAdded() {
        #expect(shows(.notDetermined) && shows(.denied))
        #expect(!shows(.notDetermined, games: false))
    }

    @Test func neverAfterAYes() {
        #expect(!shows(.authorized) && !shows(.provisional))
    }

    @Test func notNowRestsAWeekThenStopsAfterThree() {
        #expect(!shows(.notDetermined, asks: 1, until: now.addingTimeInterval(3600)))
        #expect(shows(.notDetermined, asks: 1, until: now.addingTimeInterval(-3600)))
        #expect(!shows(.notDetermined, asks: NotificationAsk.maxAsks))
    }
}

struct NotificationSnoozeTests {
    private func model() -> AppModel {
        AppModel(storeURL: URL.temporaryDirectory.appending(path: "snooze-\(UUID().uuidString).json"))
    }

    @Test func snoozeCountsAskAndRestsAWeek() {
        let m = model()
        m.snoozeNotificationCard()
        #expect(m.data.notificationAsks == 1)
        let days = Calendar.current.dateComponents([.day], from: .now, to: m.data.notificationSnoozedUntil ?? .now).day ?? 0
        #expect(days >= NotificationAsk.snoozeDays - 1)
    }

    @Test func thirdNotNowEndsTheAsking() {
        let m = model()
        for _ in 0..<NotificationAsk.maxAsks { m.snoozeNotificationCard() }
        let later = Date.now.addingTimeInterval(30 * 86_400)
        #expect(!NotificationAsk.shows(hasGames: true, status: .denied, asks: m.data.notificationAsks ?? 0, snoozedUntil: m.data.notificationSnoozedUntil, now: later))
    }

    @Test func deniedCardReturnsAfterTheWeek() {
        let m = model()
        m.snoozeNotificationCard()
        let later = Date.now.addingTimeInterval(8 * 86_400)
        #expect(NotificationAsk.shows(hasGames: true, status: .denied, asks: 1, snoozedUntil: m.data.notificationSnoozedUntil, now: later))
        #expect(!NotificationAsk.shows(hasGames: true, status: .denied, asks: 1, snoozedUntil: m.data.notificationSnoozedUntil, now: .now))
    }
}
