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
            // Alerts are off: the relay forgets this device (r052-device-delete). Retried here until it answers.
            PushRegistrar.forgetDevice()
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
        if let model, PushRegistrar.appCallsEnabled { PushRegistrar.register(token: deviceToken!, follows: model.follows, quietHours: model.data.quietHours) }
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
            let text = ns.map { ", error \($0.localizedDescription) [\($0.domain) \($0.code)]" } ?? ""
            Task { @MainActor in
                self.qaScheduleLog += "; added" + text + " (try \(attempt))"
                guard !text.isEmpty else { return }
                // 0473bc2 (Mac, both sims): "Source is not authorized" at auth 2. Say what the system thinks the app may do right now.
                self.center.getNotificationSettings { s in
                    let line = "settings auth \(s.authorizationStatus.rawValue) alert \(s.alertSetting.rawValue) center \(s.notificationCenterSetting.rawValue) lock \(s.lockScreenSetting.rawValue) sound \(s.soundSetting.rawValue) badge \(s.badgeSetting.rawValue)"
                    Task { @MainActor in self.qaScheduleLog += "; " + line }
                }
                if attempt == 1 {
                    // Decisive probe: the same add with a bare request (title only, no thread, category or interruption level). If
                    // this is accepted the refusal is about our content; if it is refused too, usernoted does not accept the app.
                    let bare = UNMutableNotificationContent()
                    bare.title = "qa probe"
                    self.center.add(UNNotificationRequest(identifier: "qa-probe", content: bare,
                                                          trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false))) { e in
                        let r = (e as NSError?).map { "refused [\($0.domain) \($0.code)]" } ?? "accepted"
                        Task { @MainActor in self.qaScheduleLog += "; bare probe \(r)" }
                    }
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
    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    nonisolated(unsafe) static let keychain = DeviceKeyStore(read: readKeychain, store: writeKeychain)

    private static func readKeychain() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data, let k = String(data: d, encoding: .utf8) {
            return k
        }
        // Migrate a key an earlier build kept in UserDefaults.
        guard let old = UserDefaults.standard.string(forKey: account) else { return nil }
        // Only forget the old copy once the Keychain has the key; if it refuses, the key stays where it was.
        if writeKeychain(old) { UserDefaults.standard.removeObject(forKey: account) }
        return old
    }

    private static func writeKeychain(_ value: String?) -> Bool {
        SecItemDelete(base as CFDictionary)
        guard let value else { return true }
        var a = base
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

    static var baseURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "PlayscribeAPIBaseURL") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Whether the app's own relay calls (follows on save, quiet hours on activation and in Settings, device registration)
    /// run. They stand down in a test host, and tests also switch them off explicitly, so a test that stubs the session sees
    /// only its own requests whatever the app does in the background.
    nonisolated(unsafe) static var appCallsEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    /// Tests point these at a stub; the app uses the plist, the shared session and the Keychain.
    nonisolated(unsafe) static var relayOverride: URL?
    nonisolated(unsafe) static var session: URLSession = .shared
    nonisolated(unsafe) static var keys: DeviceKeyStore = .keychain

    /// The push relay: device tokens, follows and the quiet window go here, not to the static feed (`baseURL`), which has no
    /// device routes. Builds without PlayscribeRelayURL cannot receive server push.
    static var relayURL: URL? {
        if let relayOverride { return relayOverride }
        guard let s = Bundle.main.object(forInfoDictionaryKey: "PlayscribeRelayURL") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Forgets what the client remembers between calls (tests start each case clean).
    static func resetForTests() { registration = nil; lastQuiet = nil; lastFollows = nil; lastTeam = nil
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
    static func register(token: String, follows: [Follow], quietHours: QuietHours? = nil) -> Task<Void, Never>? {
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
            if await registerNow(token: token, follows: follows) {
                await sendQuiet(lastQuiet, retry: true)
                if let team = lastTeam { await sendTeam(team, retry: true) }
            }
        }
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
        return false
    }

    /// DELETE /v1/devices/me: asks the relay to forget this device (r052-device-delete), used when alerts go off. A 2xx means
    /// done (the relay also answers 204 when the key is already gone) and a 401 means it no longer knows the key, so either
    /// way the stored key and what the client remembers are dropped. Offline or any other answer keeps the key, so the next
    /// time alerts are found off it tries again; it never blocks the toggle. Returns the task for tests.
    @discardableResult
    static func forgetDevice() -> Task<Void, Never>? {
        guard let url = relayURL?.appending(path: "v1/devices/me"), let key = keys.read() else { return nil }
        return Task {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return }
            if (200..<300).contains(http.statusCode) || http.statusCode == 401 {
                // Only if the key is still the one just deleted (a new registration may have stored another meanwhile).
                if keys.read() == key { keys.write(nil); registration = nil; lastFollows = nil; lastQuiet = nil }
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
    static func syncFollows(_ follows: [Follow]) -> Task<Void, Never>? {
        guard let url = relayURL?.appending(path: "v1/devices/me/follows"), keys.read() != nil,
              let body = try? Self.stableEncoder.encode(FollowsBody(follows: follows)) else { return nil }
        let signature = String(decoding: body, as: UTF8.self)
        guard signature != lastFollows else { return nil }
        lastFollows = signature
        // A later 401 registers again with this list, not the one from launch.
        registration?.follows = follows
        return Task {
            let ok = await authed(retry: true) { key in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.httpBody = body
                return request
            }
            if !ok { lastFollows = nil }
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
        guard showsTeam, relayURL != nil, keys.read() != nil else { return nil }
        lastTeam = on
        return Task { await sendTeam(on, retry: true) }
    }

    /// PATCH /v1/devices/me { quietHours }. Does nothing before the device is registered (no push can
    /// reach it then, so there is nothing to quiet) or while PlayscribeRelayURL is unset.
    @discardableResult
    static func syncQuietHours(_ q: QuietHours?) -> Task<Void, Never>? {
        guard relayURL != nil, keys.read() != nil else { return nil }
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
