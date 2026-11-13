import Foundation
import Observation
import UIKit
import Security
import UserNotifications

/// N-1: when the invitation card shows. Pure, so it is tested without the notification centre.
enum NotificationAsk {
    static let snoozeDays = 7
    static let maxAsks = 3

    static func shows(hasGames: Bool, status: UNAuthorizationStatus, asks: Int, snoozedUntil: Date?, now: Date = .now) -> Bool {
        guard hasGames, status == .notDetermined || status == .denied, asks < maxAsks else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        return true
    }
}

/// N-9, one ask per screen (Iris, 11 Nov 2026): the "Help keep your games up to date?" card waits until the alerts card (N-1) has
/// been answered, and shows on a later Library appearance, never in the session that answered it. When both are due and alerts
/// were answered earlier, the follow-list card shows alone.
enum KeepCurrentAsk {
    static func shows(hasGames: Bool, on: Bool, dismissed: Bool, alertsCardShows: Bool, alertsAnswered: Bool, answeredThisSession: Bool) -> Bool {
        hasGames && !on && !dismissed && !alertsCardShows && alertsAnswered && !answeredThisSession
    }
}

/// Local and remote notifications: asking in context (N-1, N-2), content and interruption
/// levels (N-3, N-4), foreground handling (N-7), deep links (N-6) and the badge (N-8).
@Observable
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @ObservationIgnored weak var model: AppModel?
    /// Set when the app is launched by tapping a notification, so the splash is skipped (L-3).
    var launchedFromNotification = false
    /// QA (INTERNAL): what the last notification tap delivered ("game/release"), so a test can tell "the response never arrived"
    /// from "it arrived and navigation did not follow" (96e0e39, eab123c: the tap brought the app up on the Library).
    var qaLastResponse: String?
    /// QA (INTERNAL): what schedule() decided for the last release and what the system reported ("added", "delivered=1"), so a
    /// run that finds Notification Center empty can say whether the notification was never scheduled or vanished (2537997).
    var qaScheduleLog = "none"
    /// The APNs device token, hex encoded, once registered. The backend thread owns delivery.
    private(set) var deviceToken: String?

    private let center = UNUserNotificationCenter.current()

    func attach(_ model: AppModel) {
        self.model = model
        center.delegate = self
        Task { await refreshAuthorization(); syncReleaseDayAlerts(); syncPlusLeavingSoon() }
    }

    #if INTERNAL
    /// QA (`-qaRoute alerts` / `alerts-denied`): pins the status the invitation card and Settings see.
    var qaForcedAuthorization: UNAuthorizationStatus? {
        didSet { if let s = qaForcedAuthorization { authorization = s } }
    }
    #endif

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        #if INTERNAL
        if let s = qaForcedAuthorization { authorization = s; return }
        #endif
        if authorization == .authorized || authorization == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        } else if authorization == .denied, PushRegistrar.appCallsEnabled {
            // Alerts are off: the relay forgets this device (r052-device-delete). Retried here until it answers. While "Help keep
            // my games up to date" is on, only the token goes and the follow list stays (0.5.4).
            PushRegistrar.forgetDevice(keepFollows: model?.data.keepCurrent == true)
        }
    }

    /// Shows the system prompt. Called only from the invitation card or the bell (never at launch).
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// Release-day alert (0.5.0 item 14, PR 2): one local notification at 09:00 on the day an
    /// exact-dated Wishlist game is out, "<Game> is out today on PS5". Respects the global
    /// "Notify me about" setting and a per-game Off. Vague dates (month, quarter, year) never alert.
    func syncReleaseDayAlerts() {
        guard let model, authorization == .authorized || authorization == .provisional else { return }
        let due = model.data.collection.compactMap { c -> (CatalogGame, Date)? in
            guard c.status == .wishlist, !model.data.pauseAll, model.notifyLevel(c.gameID) != .off,
                  let g = model.game(c.gameID), (g.releasePrecision ?? .day) == .day,
                  let day = g.releaseDate?.isoDay, day > .now else { return nil }
            return (g, day)
        }
        center.getPendingNotificationRequests { [center] pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix("release-day-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for (g, day) in due {
                let content = UNMutableNotificationContent()
                content.title = g.name
                content.body = "Out today on PS5"
                content.sound = .default
                // The UTC day number, at 09:00 on the device: "out today" never disagrees with the printed date.
                var parts = Date.utcCalendar.dateComponents([.year, .month, .day], from: day)
                parts.hour = 9
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: "release-day-\(g.id)", content: content, trigger: trigger))
            }
        }
    }

    /// PS Plus "Leaving soon" (0.5.0): one local reminder at 10:00 on the first of the last three days to claim
    /// a month's games, for each month still ahead. Honours its own switch, Pause all and quiet hours. Rescheduled
    /// after every plus.json load, on launch and when the switch changes; one identifier per month, so never twice.
    func syncPlusLeavingSoon() {
        guard let model else { return }
        let on = model.data.plusCardOff != true && model.data.plusLeavingSoonOff != true && !model.data.pauseAll
            && (authorization == .authorized || authorization == .provisional)
        // Everything the closure needs is worked out here, on the main actor, as plain values.
        struct Item: Sendable { var id: String; var body: String; var passive: Bool; var parts: DateComponents }
        var items: [Item] = []
        if on {
            let quiet = model.data.quietHours
            for m in PlusStore.shared.months {
                guard let fire = PlusLogic.leavingSoonFire(m) else { continue }
                items.append(Item(id: "plus-leaving-\(m.month)",
                                  body: "This month's games can be claimed until \(PlusLogic.claimByText(m)).",
                                  passive: quiet?.contains(fire) == true,
                                  parts: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)))
            }
        }
        let due = items
        center.getPendingNotificationRequests { [center] pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("plus-leaving-") })
            for i in due {
                let content = UNMutableNotificationContent()
                content.title = "PS Plus games leaving soon"
                content.body = i.body
                if i.passive { content.interruptionLevel = .passive } else { content.sound = .default }
                center.add(UNNotificationRequest(identifier: i.id, content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: i.parts, repeats: false)))
            }
        }
    }

    /// Date-move alert (0.6.0 pitch): when a watched game's PS5 date is delayed, moved earlier or
    /// newly dated, one quiet notification per change, within 72 hours of it. Honours Pause all and a
    /// per-game Off. The feed has no push for upcoming games, so this rides the Upcoming refresh.
    func notifyDateMoves() {
        guard let model, authorization == .authorized || authorization == .provisional, !model.data.pauseAll else { return }
        var done = model.data.notifiedMoves ?? []
        for c in model.data.collection where c.status == .wishlist && model.notifyLevel(c.gameID) != .off {
            guard let g = model.game(c.gameID), let igdb = g.igdbID,
                  let move = UpcomingStore.shared.extras[igdb]?.move, move.isFresh(), let line = move.line,
                  let stamp = move.movedAt else { continue }
            let key = "\(igdb):\(stamp)"
            guard !done.contains(key) else { continue }
            done.insert(key)
            let content = UNMutableNotificationContent()
            content.title = g.name
            content.body = [line, g.ps5DateLine.flatMap { $0 == "Release date TBA" ? nil : $0 }].compactMap { $0 }.joined(separator: ". ")
            content.interruptionLevel = .passive
            center.add(UNNotificationRequest(identifier: "date-move-\(key)", content: content, trigger: nil))
        }
        model.data.notifiedMoves = done
    }

    func didRegister(token: Data) {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        if let model, PushRegistrar.appCallsEnabled { PushRegistrar.register(token: deviceToken!, follows: model.follows, quietHours: model.data.quietHours, hourly: model.data.keepCurrent == true) }
    }

    func updateBadge(_ count: Int) {
        Task { try? await center.setBadgeCount(count) }
    }

    #if INTERNAL
    private var qaRequests: [String: UNNotificationRequest] = [:]
    /// Adds, logs, and retries a refused add (the request is kept here because it is not Sendable and cannot ride the completion).
    private func qaAdd(_ request: UNNotificationRequest, attempt: Int) {
        qaRequests[request.identifier] = request
        let id = request.identifier
        center.add(request) { error in
            let ns = error as NSError?
            // Quinn's terms for #422: a refusal before this simulator ever accepted an add is "simulator refused"; one after a
            // success is an app failure. The flag lives in the app's own defaults, so an erase or reinstall clears it.
            let key = "qaNotifAddOK"
            let hadSuccess = UserDefaults.standard.bool(forKey: key)
            if ns == nil { UserDefaults.standard.set(true, forKey: key) }
            let text = ns.map { ", error \($0.localizedDescription) [\($0.domain) \($0.code)] (earlier success on this sim: \(hadSuccess ? "yes" : "no"))" } ?? ""
            Task { @MainActor in
                self.qaScheduleLog += "; added" + text + " (try \(attempt))"
                guard !text.isEmpty else { return }
                // 0473bc2 (Mac, both sims): "Source is not authorized" at auth 2. Say what the system thinks the app may do right now.
                self.center.getNotificationSettings { s in
                    let line = "settings auth \(s.authorizationStatus.rawValue) alert \(s.alertSetting.rawValue) center \(s.notificationCenterSetting.rawValue) lock \(s.lockScreenSetting.rawValue) sound \(s.soundSetting.rawValue) badge \(s.badgeSetting.rawValue)"
                    Task { @MainActor in self.qaScheduleLog += "; " + line }
                }
                if attempt < 5, let r = self.qaRequests[id] {
                    try? await Task.sleep(for: .seconds(3))
                    self.qaAdd(r, attempt: attempt + 1)
                }
            }
        }
    }
    #endif

    /// Builds the notification for a release that reached On PS5 (N-4) and schedules it locally.
    /// Remote pushes from the backend carry the same fields.
    func schedule(release: Release, game: CatalogGame?, level: NotifyLevel, pauseAll: Bool, delay: TimeInterval, model: AppModel) {
        guard let game, release.ps5State == .onPS5, !pauseAll else {
            #if INTERNAL
            qaScheduleLog = "\(release.id): not scheduled (game \(game == nil ? "nil" : "ok"), state \(release.ps5State), pauseAll \(pauseAll))"
            #endif
            return
        }
        guard level == .all || (level == .major && release.kind.countsAsMajor) else { return }
        if model.data.knownReported?.contains(release.id) == true, model.data.notified[release.id] != nil {
            // N-11: the quiet Reported alert was this release's one push. Replace it in place,
            // silently, with the On PS5 text.
            let c = Self.content(for: release, game: game, badge: model.badgeCount)
            c.interruptionLevel = .passive
            c.sound = nil
            c.badge = nil
            center.add(UNNotificationRequest(identifier: release.id, content: c, trigger: nil))
            return
        }
        guard model.data.notified[release.id] == nil else { return }
        model.data.notified[release.id] = .now

        let content = Self.content(for: release, game: game, badge: model.badgeCount + 1)
        // Quiet hours: arrive silently in Notification Center, never held back past the window end.
        if model.data.quietHours?.contains(Date().addingTimeInterval(max(1, delay))) == true {
            content.interruptionLevel = .passive
            content.sound = nil
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(identifier: release.id, content: content, trigger: trigger)
        #if INTERNAL
        qaScheduleLog = "\(release.id): adding, due in \(Int(max(1, delay))) s"
        // "Source is not authorized" was seen at auth 2 right after a grant (5000f21): the daemon can lag the status. Retry the add
        // up to 3 times, 2 s apart, and log every attempt, so the run shows whether a retry cures it.
        qaAdd(request, attempt: 1)
        // 0 not determined, 1 denied, 2 authorized, 3 provisional, 4 ephemeral. A denied or never-answered permission is why a fresh
        // simulator can show no notification at all (r053-deflake-notification-tap), so the UI test reads it.
        center.getNotificationSettings { s in
            let status = s.authorizationStatus.rawValue   // the settings object is not Sendable; send only the Int
            Task { @MainActor in self.qaScheduleLog += "; auth \(status)" }
        }
        let releaseID = release.id
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, delay) + 2) { [center] in
            center.getDeliveredNotifications { list in
                let ids = list.map(\.request.identifier)
                Task { @MainActor in
                    self.qaScheduleLog += "; delivered after due: \(ids.contains(releaseID) ? "yes" : "no") (\(ids.count) in list)"
                }
            }
        }
        #else
        center.add(request)
        #endif

        // Make the release visible once it is due, whether or not the notification is shown.
        Task { [weak model] in
            try? await Task.sleep(for: .seconds(max(1, delay)))
            model?.tick()
            if let model { self.updateBadge(model.badgeCount) }
        }
    }

    static func content(for release: Release, game: CatalogGame, badge: Int) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = game.name
        c.body = body(for: release)
        c.threadIdentifier = game.id
        c.interruptionLevel = release.kind.countsAsMajor ? .active : .passive
        c.sound = release.kind.countsAsMajor ? .default : nil
        c.badge = NSNumber(value: badge)
        c.userInfo = ["gameId": game.id, "releaseId": release.id]
        c.categoryIdentifier = "release"
        return c
    }

    /// 0.5.0 copy (handoff/0.5.0/alert-and-field-guide-copy.md): "Update 1.1: <headline>", one line of
    /// at most 60 characters, no counts (counts live in titles). Fallback when there is no headline.
    static func body(for release: Release) -> String {
        guard let head = headline(for: release) else { return countsLine(release) ?? "A new update is out" }
        return fit("\(release.displayName): \(head)")
    }

    /// The first PS5 change line, or the editorial push line; the part before any colon or semicolon.
    static func headline(for release: Release) -> String? {
        let raw = release.pushLine.flatMap { PCOnly.matches($0) ? nil : $0 } ?? release.ps5KeyChanges.first
        guard let raw else { return nil }
        var line = String(raw.split(whereSeparator: { $0 == ":" || $0 == ";" }).first ?? Substring(raw))
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,"))
        if let first = line.first, line.dropFirst().first?.isLowercase == true { line = first.lowercased() + line.dropFirst() }
        return line.isEmpty ? nil : line
    }

    /// "3 new, 5 fixes, 2 PS5 only" from the feed digest (zero counts left out); nil when nothing counted.
    static func countsLine(_ release: Release) -> String? {
        guard let d = release.digest else { return nil }
        let parts = [(d.new, "new"), (d.fixed, d.fixed == 1 ? "fix" : "fixes"), (d.ps5, "PS5 only")]
            .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return parts.count >= 2 ? parts.joined(separator: ", ") : nil
    }

    /// "<Game>, 3 new updates" when several arrive at once; the game name otherwise.
    static func title(game: CatalogGame, count: Int) -> String { count > 1 ? "\(game.name), \(count) new updates" : game.name }

    /// Several at once: "Latest: <version>, <headline>".
    static func latestBody(for release: Release) -> String {
        guard let head = headline(for: release) else { return "New updates are out" }
        return fit("Latest: \(release.displayName), \(head)")
    }

    private static func fit(_ text: String, limit: Int = 60) -> String {
        guard text.count > limit else { return text }
        var cut = String(text.prefix(limit - 1))
        if let sp = cut.lastIndex(of: " ") { cut = String(cut[..<sp]) }
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,:")) + "…"
    }

    /// Registers the category so hidden previews read "A game you follow has an update".
    func registerCategories() {
        let category = UNNotificationCategory(identifier: "release", actions: [], intentIdentifiers: [],
                                              hiddenPreviewsBodyPlaceholder: "A game you follow has an update", options: [])
        center.setNotificationCategories([category])
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// N-7: no banner in the foreground; the list and badge only, and the app shows its own pill.
    ///
    /// The completion-handler form, with the handler called on the main actor. The `async` form let Swift's concurrency runtime call the
    /// handler from a cooperative thread, and UIKit then aborted ("Call must be made on main thread", in
    /// `_updateSnapshotAndStateRestorationWithAction`): tapping a release notification crashed the app (2e8f3d2 Mac crash report).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        let gameID = info["gameId"] as? String
        let releaseID = info["releaseId"] as? String
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            if let gameID, let releaseID { self.model?.releaseArrivedInForeground(gameID: gameID, releaseID: releaseID) }
            done([.badge, .list])
        }
    }

    /// N-6: tapping opens that release in whatever pose the device is in. The handler is called on the main actor (see above).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let gameID = info["gameId"] as? String
        let releaseID = info["releaseId"] as? String
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            if let gameID, let releaseID {
                self.launchedFromNotification = true
                #if INTERNAL
                self.qaLastResponse = "\(gameID)/\(releaseID); model \(self.model == nil ? "nil" : "set")"
                #endif
                self.model?.openRelease(gameID: gameID, releaseID: releaseID)
            }
            done()
        }
    }
}

/// Where the relay's deviceKey lives. The key is a bearer secret, so it is in the Keychain (this device only, readable after
/// the first unlock), not in UserDefaults. A key left in UserDefaults by an earlier build moves over on first read.
nonisolated struct DeviceKeyStore {
    var read: () -> String?
    var store: (String?) -> Bool

    /// Stores (or, with nil, forgets) the key. False when the Keychain refused it, for example in an unsigned build.
    @discardableResult func write(_ value: String?) -> Bool { store(value) }

    private static let service = "co.codeconnectors.playscribe.push"
    private static let account = "deviceKey"
    /// A key an earlier install of the app left in the Keychain, held only until the relay has deleted its record.
    private static let staleAccount = "staleDeviceKey"
    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    nonisolated(unsafe) static let keychain = DeviceKeyStore(read: { readKeychain(account) }, store: { writeKeychain($0, account) })
    nonisolated(unsafe) static let staleKeychain = DeviceKeyStore(read: { readKeychain(staleAccount, migrate: false) }, store: { writeKeychain($0, staleAccount) })

    private static func readKeychain(_ account: String, migrate: Bool = true) -> String? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data, let k = String(data: d, encoding: .utf8) {
            return k
        }
        // Migrate a key an earlier build kept in UserDefaults.
        guard migrate, let old = UserDefaults.standard.string(forKey: account) else { return nil }
        // Only forget the old copy once the Keychain has the key; if it refuses, the key stays where it was.
        if writeKeychain(old, account) { UserDefaults.standard.removeObject(forKey: account) }
        return old
    }

    private static func writeKeychain(_ value: String?, _ account: String) -> Bool {
        SecItemDelete(base(account) as CFDictionary)
        guard let value else { return true }
        var a = base(account)
        a[kSecValueData as String] = Data(value.utf8)
        a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(a as CFDictionary, nil) == errSecSuccess
    }

    /// A store that lives and dies with the process, for tests.
    static func memory(_ initial: String? = nil) -> DeviceKeyStore {
        final class Box: @unchecked Sendable { var value: String?; init(_ v: String?) { value = v } }
        let box = Box(initial)
        return DeviceKeyStore(read: { box.value }, store: { box.value = $0; return true })
    }
}

/// Registers the device with the push relay (docs/push-relay.md): POST /v1/devices returns a deviceKey used as the Bearer token
/// for later calls. Does nothing until PlayscribeRelayURL is set. A request the relay answers with anything but 2xx counts as
/// failed; a 401 (the relay no longer knows the key) forgets the key, registers again and retries once.
enum PushRegistrar {
    struct Follow: Encodable { var gameId: String?; var igdbId: Int?; var notify: String }
    private struct Body: Encodable { var apnsToken: String; var environment: String; var follows: [Follow] }
    private struct Reply: Decodable { var deviceKey: String }

    // MARK: "Help keep my games up to date" (0.5.4): the follow list without alerts.
    // What leaves the phone for this is the ids below and the relay's random key, nothing else (design note "What leaves the
    // phone"; docs/api.md "Follow list without alerts"). `keepCurrentBody` is the one place that shapes the request, and
    // PushRegistrarTests pins its keys, so a field cannot be added without the test failing; the relay refuses one too.

    /// One followed game as an id only: our game id, or the IGDB number for a game added by hand. Never both, never a level.
    struct IdFollow: Encodable, Equatable {
        var gameId: String?
        var igdbId: Int?
        enum CodingKeys: String, CodingKey { case gameId, igdbId }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let gameId { try c.encode(gameId, forKey: .gameId) } else if let igdbId { try c.encode(igdbId, forKey: .igdbId) }
        }
    }
    private struct IdFollowsBody: Encodable { var follows: [IdFollow] }
    private struct HourlyBody: Encodable { var hourly: Bool }

    static func idFollows(_ follows: [Follow]) -> [IdFollow] {
        follows.compactMap { f in
            if let g = f.gameId { return IdFollow(gameId: g) }
            if let i = f.igdbId { return IdFollow(igdbId: i) }
            return nil
        }
    }

    /// The body of `POST /v1/follows` and of the list update on a record without alerts: `{ follows: [{ gameId } | { igdbId }] }`.
    static func keepCurrentBody(_ follows: [Follow]) -> Data? { try? stableEncoder.encode(IdFollowsBody(follows: idFollows(follows))) }

    /// UserDefaults: "follows" while the stored key names a record made by `POST /v1/follows` (no alerts). Such a record takes
    /// ids only, and a 401 on it registers again through that route. Absent or anything else: a push registration.
    static let recordKindKey = "keepCurrentRecord"
    /// UserDefaults: when the list (or the "still here") last reached the relay for this purpose. Settings shows it.
    static let lastSentKey = "keepCurrentLastSent"
    private static var recordIsFollowsOnly: Bool {
        get { UserDefaults.standard.string(forKey: recordKindKey) == "follows" }
        set { if newValue { UserDefaults.standard.set("follows", forKey: recordKindKey) } else { UserDefaults.standard.removeObject(forKey: recordKindKey) } }
    }
    static var keepCurrentLastSent: Date? { UserDefaults.standard.object(forKey: lastSentKey) as? Date }
    private static func markSent() { UserDefaults.standard.set(Date(), forKey: lastSentKey) }
    /// The "still here": an unchanged list is sent again once a week, so the relay can renew the record's 90-day expiry.
    static let stillHereDays = 7
    /// The last list handed to `syncKeepCurrent`, so a 401 on a record without alerts can register it again.
    nonisolated(unsafe) private static var keepCurrentFollows: [Follow]?
    /// The last `hourly` value sent, so a save that changes nothing sends nothing.
    nonisolated(unsafe) private static var lastHourly: Bool?
    /// The first `POST /v1/follows` while it is out, so a second call in that window never makes a second record.
    nonisolated(unsafe) private static var pendingFollowsOnly: Task<Bool, Never>?

    /// The Settings switch, and every save while it is on. On: a device with no record yet registers through `POST /v1/follows`
    /// once it has a follow (an empty list is never sent: a new record spends one of the relay's daily slots); a record
    /// without alerts gets the list as ids; a push device gets `hourly: true`. Off: the alerts-free record is deleted, a push
    /// device's flag is cleared. Nothing while PlayscribeRelayURL is unset.
    @discardableResult
    static func syncKeepCurrent(_ on: Bool, follows: [Follow]) -> Task<Void, Never>? {
        guard relayURL != nil else { return nil }
        keepCurrentFollows = follows
        if on {
            if keys.read() == nil {
                // Single flight (Quinn, #455 capture: two POSTs 2 s apart, the first record orphaned): while the first POST is
                // out, a second call never makes another record. It waits, then sends the latest list as an update if it changed.
                if let pending = pendingFollowsOnly {
                    return Task {
                        // Still on (an off in the meantime clears the list) and the POST made a record: send the latest list.
                        guard await pending.value, let latest = keepCurrentFollows else { return }
                        await syncKeepCurrent(true, follows: latest)?.value
                    }
                }
                guard !follows.isEmpty, let body = keepCurrentBody(follows) else { return nil }
                // Cleared before the result is handed on, so a call that waited on it sees the key, not the pending POST.
                let first = Task { () -> Bool in let ok = await registerFollowsOnly(body); pendingFollowsOnly = nil; return ok }
                pendingFollowsOnly = first
                return Task { _ = await first.value }
            }
            if recordIsFollowsOnly { return syncFollows(follows, stillHere: stillHereDue) }
            guard lastHourly != true else { return nil }
            return Task { await sendHourly(true, retry: true) }
        }
        keepCurrentFollows = nil
        // Off while the first POST is out: wait for its key, then delete that record, so none is left behind.
        if let pending = pendingFollowsOnly {
            return Task {
                guard await pending.value else { return }
                await syncKeepCurrent(false, follows: follows)?.value
            }
        }
        guard keys.read() != nil else { return nil }
        if recordIsFollowsOnly { return forgetDevice() }
        guard lastHourly != false else { return nil }
        return Task { await sendHourly(false, retry: true) }
    }

    private static var stillHereDue: Bool {
        guard let last = keepCurrentLastSent else { return true }
        return Date().timeIntervalSince(last) >= Double(stillHereDays) * 86_400
    }

    /// POST /v1/follows: ids only, no key yet. True when the relay answered 2xx with a key, which is then stored.
    private static func registerFollowsOnly(_ body: Data) async -> Bool {
        guard let url = relayURL?.appending(path: "v1/follows") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return false }
        keys.write(reply.deviceKey)
        recordIsFollowsOnly = true
        registration = nil
        lastFollows = String(decoding: body, as: UTF8.self)
        markSent()
        return true
    }

    @discardableResult
    private static func sendHourly(_ on: Bool, retry: Bool) async -> Bool {
        guard let url = relayURL?.appending(path: "v1/devices/me") else { return false }
        let sent = await authed(retry: retry) { key in
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONEncoder().encode(HourlyBody(hourly: on))
            return request
        }
        if sent { lastHourly = on; if on { markSent() } }
        return sent
    }

    static var baseURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "PlayscribeAPIBaseURL") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Whether the app's own relay calls (follows on save, quiet hours on activation and in Settings, device registration)
    /// run. They stand down in a test host, and tests also switch them off explicitly, so a test that stubs the session sees
    /// only its own requests whatever the app does in the background.
    /// `-qaNoRelay` (UI tests): the app makes no relay call at all, so a test that taps a switch leaves no record behind.
    nonisolated(unsafe) static var appCallsEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        && !ProcessInfo.processInfo.arguments.contains("-qaNoRelay")

    /// Tests point these at a stub; the app uses the plist, the shared session and the Keychain.
    nonisolated(unsafe) static var relayOverride: URL?
    nonisolated(unsafe) static var session: URLSession = .shared
    nonisolated(unsafe) static var keys: DeviceKeyStore = .keychain
    nonisolated(unsafe) static var staleKeys: DeviceKeyStore = .staleKeychain

    /// The push relay: device tokens, follows and the quiet window go here, not to the static feed (`baseURL`), which has no
    /// device routes. Builds without PlayscribeRelayURL cannot receive server push.
    static var relayURL: URL? {
        if let relayOverride { return relayOverride }
        guard let s = Bundle.main.object(forInfoDictionaryKey: "PlayscribeRelayURL") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Forgets what the client remembers between calls (tests start each case clean).
    static func resetForTests() { registration = nil; lastQuiet = nil; lastFollows = nil; lastTeam = nil; lastHourly = nil; keepCurrentFollows = nil
        pendingFollowsOnly = nil; pendingStaleDelete = nil
        UserDefaults.standard.removeObject(forKey: recordKindKey); UserDefaults.standard.removeObject(forKey: lastSentKey)
        #if DEBUG
        showsTeamForTests = nil
        #endif
    }

    /// What the last registration sent, so a 401 can register again without asking the app.
    private struct Registration { var token: String; var follows: [Follow] }
    nonisolated(unsafe) private static var registration: Registration?
    nonisolated(unsafe) private static var lastQuiet: QuietWindow?
    /// Internal builds only: the "Team alerts" choice (UserDefaults `teamAlerts`), sent to the relay as `team`. Nil until the
    /// tester has chosen, so a normal build never sends the field.
    nonisolated(unsafe) private static var lastTeam: Bool?
    static let teamKey = "teamAlerts"
    #if DEBUG
    /// Tests stand in for the receipt check (a test host is never an App Store build). Not compiled into a release build.
    nonisolated(unsafe) static var showsTeamForTests: Bool?
    private static var showsTeam: Bool { showsTeamForTests ?? BuildChannel.showsTeamAlerts }
    #else
    private static var showsTeam: Bool { BuildChannel.showsTeamAlerts }
    #endif

    @discardableResult
    static func register(token: String, follows: [Follow], quietHours: QuietHours? = nil, hourly: Bool = false) -> Task<Void, Never>? {
        guard relayURL != nil else { return nil }
        lastQuiet = quietWindow(quietHours)
        if showsTeam {
            lastTeam = UserDefaults.standard.object(forKey: teamKey) as? Bool
        } else {
            // An App Store build installed over a TestFlight one: the tester's "on" is still in UserDefaults and the relay record
            // still says team=true. Say team=false once; sendTeam clears the stored choice when the relay has it.
            lastTeam = UserDefaults.standard.bool(forKey: teamKey) ? false : nil
        }
        return Task {
            // A record made without alerts (the keep-current switch) takes the token in place: same key, no second record.
            if recordIsFollowsOnly, keys.read() != nil, await addToken(token, follows: follows) {
                await sendQuiet(lastQuiet, retry: true)
                if let team = lastTeam { await sendTeam(team, retry: true) }
                return
            }
            // bug-relay-optin-cleared-token: the record this key names may have lost its token (the Feed job reports dead
            // tokens and the relay clears them; a follow-list record keeps only its ids). Put this launch's token back on the
            // same record first, so the registration below finds it and no second record is made. Token and environment only;
            // unchanged, it costs the relay no write. A failure (401: the record is gone) falls through to registering afresh.
            if keys.read() != nil { await sendToken(token) }
            if await registerNow(token: token, follows: follows) {
                await sendQuiet(lastQuiet, retry: true)
                if let team = lastTeam { await sendTeam(team, retry: true) }
                if hourly { await sendHourly(true, retry: true) }
            }
        }
    }

    private struct TokenBody: Encodable { var apnsToken: String; var environment: String }

    /// PATCH /v1/devices/me { apnsToken, environment } with the stored key: the one request that puts a token on a record.
    private static func tokenRequest(_ token: String) -> URLRequest? {
        guard let url = relayURL?.appending(path: "v1/devices/me"), let key = keys.read() else { return nil }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(TokenBody(apnsToken: token, environment: environment))
        return request
    }

    /// A push device's launch: its token back on its own record (see `register`). No retry and no re-registration here.
    private static func sendToken(_ token: String) async {
        guard let request = tokenRequest(token) else { return }
        _ = try? await session.data(for: request)
    }

    /// PATCH /v1/devices/me { apnsToken, environment } on a record that had no alerts: it becomes this device's push record and
    /// then takes the list with its levels. False (so the caller registers afresh) when the relay no longer knows the key.
    private static func addToken(_ token: String, follows: [Follow]) async -> Bool {
        guard let request = tokenRequest(token) else { return false }
        guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            keys.write(nil)
            recordIsFollowsOnly = false
            return false
        }
        recordIsFollowsOnly = false
        registration = Registration(token: token, follows: follows)
        lastHourly = true
        lastFollows = nil
        await syncFollows(follows)?.value
        return true
    }

    /// POST /v1/devices. True when the relay answered 2xx with a key, which is then stored.
    private static func registerNow(token: String, follows: [Follow]) async -> Bool {
        guard let url = relayURL?.appending(path: "v1/devices") else { return false }
        registration = Registration(token: token, follows: follows)
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Body(apnsToken: token, environment: environment, follows: follows))
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return false }
        keys.write(reply.deviceKey)
        return true
    }

    /// Sends a request with the device's Bearer key. False when there is no key, the request fails, or the relay answers
    /// anything but 2xx. On a 401 the key is forgotten, the device registers again and the request is retried once.
    private static func authed(retry: Bool, _ make: (String) -> URLRequest?) async -> Bool {
        guard let key = keys.read(), let request = make(key) else { return false }
        guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return false }
        if (200..<300).contains(http.statusCode) { return true }
        if http.statusCode == 401, retry, let r = registration {
            keys.write(nil)
            guard await registerNow(token: r.token, follows: r.follows) else { return false }
            await sendQuiet(lastQuiet, retry: false)
            if let team = lastTeam { await sendTeam(team, retry: false) }
            return await authed(retry: false, make)
        }
        // A record without alerts the relay no longer knows (expired after 90 days, say): make it again, ids only.
        if http.statusCode == 401, retry, recordIsFollowsOnly, let follows = keepCurrentFollows, !follows.isEmpty, let body = keepCurrentBody(follows) {
            keys.write(nil)
            guard await registerFollowsOnly(body) else { return false }
            return await authed(retry: false, make)
        }
        return false
    }

    /// A fresh install (no saved state) that finds a key: the Keychain outlives an uninstall, UserDefaults and the app's state
    /// do not, so the key names a record this install knows nothing about, not even whether it has alerts (Quinn's #455
    /// stale-key capture: quietHours sent to a record without alerts, then no list updates). The key moves to the stale slot
    /// and the relay is asked to delete its record, so a reinstall starts clean and "deleted when you delete the app and install it again" stays true.
    /// Call before any other relay call of the launch.
    @discardableResult
    static func dropStaleKey() -> Task<Void, Never>? {
        guard let key = keys.read() else { return nil }
        if staleKeys.write(key) { keys.write(nil) } else { return nil }
        registration = nil; lastFollows = nil; lastQuiet = nil; lastHourly = nil; keepCurrentFollows = nil
        recordIsFollowsOnly = false
        UserDefaults.standard.removeObject(forKey: lastSentKey)
        return deleteStaleRecord()
    }

    /// DELETE /v1/devices/me with the key an earlier install left. A 2xx (or a 401: already gone) drops it; offline or any
    /// other answer keeps it for the next activation. It never touches this install's own key.
    /// Single flight (Mac capture at eb42735: the launch's delete and the first activation's retry went 43 ms apart, both
    /// 204): while one DELETE is out, a second call waits for it instead of sending another.
    @discardableResult
    static func deleteStaleRecord() -> Task<Void, Never>? {
        if let pending = pendingStaleDelete { return Task { await pending.value } }
        guard let url = relayURL?.appending(path: "v1/devices/me"), let key = staleKeys.read() else { return nil }
        let task = Task {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            if let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) || http.statusCode == 401, staleKeys.read() == key {
                staleKeys.write(nil)
            }
            pendingStaleDelete = nil
        }
        pendingStaleDelete = task
        return task
    }
    nonisolated(unsafe) private static var pendingStaleDelete: Task<Void, Never>?

    /// DELETE /v1/devices/me: asks the relay to forget this device (r052-device-delete), used when alerts go off. A 2xx means
    /// done (the relay also answers 204 when the key is already gone) and a 401 means it no longer knows the key, so either
    /// way the stored key and what the client remembers are dropped. Offline or any other answer keeps the key, so the next
    /// time alerts are found off it tries again; it never blocks the toggle. Returns the task for tests.
    @discardableResult
    static func forgetDevice(keepFollows: Bool = false) -> Task<Void, Never>? {
        guard let url = relayURL?.appending(path: "v1/devices/me"), let key = keys.read() else { return nil }
        // Alerts off while "Help keep my games up to date" is on: the token goes, the record stays (ids only from here, and it
        // now expires like any record without alerts). Nothing to do when the record never had a token.
        if keepFollows {
            guard !recordIsFollowsOnly else { return nil }
            return Task {
                var request = URLRequest(url: url)
                request.httpMethod = "PATCH"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.httpBody = Data("{\"apnsToken\":null}".utf8)
                guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
                if keys.read() == key { recordIsFollowsOnly = true; registration = nil; lastFollows = nil; lastQuiet = nil }
            }
        }
        return Task {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return }
            if (200..<300).contains(http.statusCode) || http.statusCode == 401 {
                // Only if the key is still the one just deleted (a new registration may have stored another meanwhile).
                if keys.read() == key {
                    keys.write(nil); registration = nil; lastFollows = nil; lastQuiet = nil; lastHourly = nil
                    recordIsFollowsOnly = false
                    UserDefaults.standard.removeObject(forKey: lastSentKey)
                }
            }
        }
    }

    /// The last follows list sent, so an unchanged list costs no request (the relay's free plan allows 1,000 writes a day).
    nonisolated(unsafe) private static var lastFollows: String?
    private struct FollowsBody: Encodable { var follows: [Follow] }
    /// Sorted keys: the encoded list is the dedupe signature, and Swift's JSONEncoder does not promise one key order from
    /// one encode to the next, so an unchanged list could look changed and be sent again.
    private static let stableEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    /// PUT /v1/devices/me/follows: the followed games and their notify level, when they change. Nothing before the device is
    /// registered or while PlayscribeRelayURL is unset. A failed send forgets the list, so the next change sends it again.
    @discardableResult
    /// `pushOnly`: the save with the keep-current switch off, which speaks only for a push device; a record without alerts
    /// then is being deleted (or is the switch's to update), so nothing is sent for it.
    static func syncFollows(_ follows: [Follow], stillHere: Bool = false, pushOnly: Bool = false) -> Task<Void, Never>? {
        guard let url = relayURL?.appending(path: "v1/devices/me/follows"), keys.read() != nil else { return nil }
        // A record without alerts takes ids only (the relay refuses a level); a push device's list carries its levels.
        let idsOnly = recordIsFollowsOnly
        if pushOnly && idsOnly { return nil }
        guard let body = idsOnly ? keepCurrentBody(follows) : try? Self.stableEncoder.encode(FollowsBody(follows: follows)) else { return nil }
        let signature = String(decoding: body, as: UTF8.self)
        // The weekly "still here" sends an unchanged list again, on a record without alerts only.
        guard signature != lastFollows || (stillHere && idsOnly) else { return nil }
        lastFollows = signature
        // A later 401 registers again with this list, not the one from launch.
        registration?.follows = follows
        if idsOnly { keepCurrentFollows = follows }
        return Task {
            let ok = await authed(retry: true) { key in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.httpBody = body
                return request
            }
            if !ok { lastFollows = nil } else if idsOnly { markSent() }
        }
    }

    /// The quiet window as the relay needs it: minutes since midnight and the IANA zone, so daylight saving
    /// is the relay's to apply. Absent when quiet hours is off (`null` clears it).
    struct QuietWindow: Encodable, Equatable { var from: Int; var until: Int; var timeZone: String }
    private struct QuietBody: Encodable {
        var quietHours: QuietWindow?
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(quietHours, forKey: .quietHours)   // an explicit null when off
        }
        enum CodingKeys: String, CodingKey { case quietHours }
    }

    static func quietWindow(_ q: QuietHours?, timeZone: TimeZone = .current) -> QuietWindow? {
        guard let q, q.from != q.until else { return nil }
        return QuietWindow(from: q.from, until: q.until, timeZone: timeZone.identifier)
    }

    @discardableResult
    private static func sendQuiet(_ window: QuietWindow?, retry: Bool) async -> Bool {
        guard let url = relayURL?.appending(path: "v1/devices/me") else { return false }
        return await authed(retry: retry) { key in
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONEncoder().encode(QuietBody(quietHours: window))
            return request
        }
    }

    private struct TeamBody: Encodable { var team: Bool }

    @discardableResult
    private static func sendTeam(_ on: Bool, retry: Bool) async -> Bool {
        guard let url = relayURL?.appending(path: "v1/devices/me") else { return false }
        let sent = await authed(retry: retry) { key in
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONEncoder().encode(TeamBody(team: on))
            return request
        }
        // The relay now has team=false for an App Store build: forget the old "on" so this is never sent again.
        if sent, !on, !showsTeam { UserDefaults.standard.removeObject(forKey: teamKey) }
        return sent
    }

    /// PATCH /v1/devices/me { team }: development and TestFlight builds only (the Settings "Team alerts" toggle; the relay sends
    /// team-only pushes to devices that opted in). Does nothing on an App Store build, before the device is registered, or while
    /// PlayscribeRelayURL is unset.
    @discardableResult
    static func syncTeam(_ on: Bool) -> Task<Void, Never>? {
        // A record without alerts takes `hourly` and ids only; the relay answers 400 to anything else.
        guard showsTeam, relayURL != nil, keys.read() != nil, !recordIsFollowsOnly else { return nil }
        lastTeam = on
        return Task { await sendTeam(on, retry: true) }
    }

    /// PATCH /v1/devices/me { quietHours }. Does nothing before the device is registered (no push can
    /// reach it then, so there is nothing to quiet), on a record without alerts (the same reason; the relay answers 400:
    /// Quinn's #455 capture), or while PlayscribeRelayURL is unset.
    @discardableResult
    static func syncQuietHours(_ q: QuietHours?) -> Task<Void, Never>? {
        guard relayURL != nil, keys.read() != nil, !recordIsFollowsOnly else { return nil }
        lastQuiet = quietWindow(q)
        let window = lastQuiet
        return Task { await sendQuiet(window, retry: true) }
    }
}

extension AppModel {
    var follows: [PushRegistrar.Follow] {
        data.collection.map { c in
            let g = game(c.gameID)
            let custom = g?.custom == true || c.gameID.hasPrefix("igdb-")
            return PushRegistrar.Follow(gameId: custom ? nil : c.gameID, igdbId: g?.igdbID, notify: notifyLevel(c.gameID).rawValue)
        }
    }
}
