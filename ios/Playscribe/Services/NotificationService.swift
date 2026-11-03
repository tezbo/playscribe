import Foundation
import Observation
import UIKit
import UserNotifications

/// Local and remote notifications: asking in context (N-1, N-2), content and interruption
/// levels (N-3, N-4), foreground handling (N-7), deep links (N-6) and the badge (N-8).
@Observable
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @ObservationIgnored weak var model: AppModel?
    /// Set when the app is launched by tapping a notification, so the splash is skipped (L-3).
    var launchedFromNotification = false
    /// The APNs device token, hex encoded, once registered. The backend thread owns delivery.
    private(set) var deviceToken: String?

    private let center = UNUserNotificationCenter.current()

    func attach(_ model: AppModel) {
        self.model = model
        center.delegate = self
        Task { await refreshAuthorization(); syncReleaseDayAlerts() }
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        if authorization == .authorized || authorization == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
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
                content.title = "\(g.name) is out today on PS5"
                content.sound = .default
                var parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
                parts.hour = 9
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: "release-day-\(g.id)", content: content, trigger: trigger))
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
        if let model { PushRegistrar.register(token: deviceToken!, follows: model.follows) }
    }

    func updateBadge(_ count: Int) {
        Task { try? await center.setBadgeCount(count) }
    }

    /// Builds the notification for a release that reached On PS5 (N-4) and schedules it locally.
    /// Remote pushes from the backend carry the same fields.
    func schedule(release: Release, game: CatalogGame?, level: NotifyLevel, pauseAll: Bool, delay: TimeInterval, model: AppModel) {
        guard let game, release.ps5State == .onPS5, !pauseAll else { return }
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
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(identifier: release.id, content: content, trigger: trigger)
        center.add(request)

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

    /// N-4: "<Display name> is live on PS5: <short line>." under about 110 characters, one colon.
    static func body(for release: Release) -> String {
        let head = "\(release.displayName) is live on PS5"
        var line = release.pushLine.flatMap { PCOnly.matches($0) ? nil : $0 }
        if line == nil {
            // The two shortest key-change headlines: the part before any colon or semicolon.
            let heads = release.ps5KeyChanges.map { k in
                String(k.split(whereSeparator: { $0 == ":" || $0 == ";" }).first ?? Substring(k)).trimmingCharacters(in: .whitespaces)
            }.sorted { $0.count < $1.count }.prefix(2)
            if !heads.isEmpty { line = heads.joined(separator: ", and ") }
        }
        guard var line, !line.isEmpty else { return head + "." }
        if let first = line.first, line.dropFirst().first?.isLowercase == true { line = first.lowercased() + line.dropFirst() }
        var text = "\(head): \(line)"
        if text.count > 109 {
            text = String(text.prefix(108))
            if let cut = text.lastIndex(of: " ") { text = String(text[..<cut]) }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        }
        return text.hasSuffix(".") ? text : text + "."
    }

    /// Registers the category so hidden previews read "New update" (N-4).
    func registerCategories() {
        let category = UNNotificationCategory(identifier: "release", actions: [], intentIdentifiers: [],
                                              hiddenPreviewsBodyPlaceholder: "New update", options: [])
        center.setNotificationCategories([category])
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// N-7: no banner in the foreground; the list and badge only, and the app shows its own pill.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        let gameID = info["gameId"] as? String
        let releaseID = info["releaseId"] as? String
        await MainActor.run {
            if let gameID, let releaseID { self.model?.releaseArrivedInForeground(gameID: gameID, releaseID: releaseID) }
        }
        return [.badge, .list]
    }

    /// N-6: tapping opens that release in whatever pose the device is in.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let gameID = info["gameId"] as? String, let releaseID = info["releaseId"] as? String else { return }
        await MainActor.run {
            self.launchedFromNotification = true
            self.model?.openRelease(gameID: gameID, releaseID: releaseID)
        }
    }
}

/// Registers the device with the backend (docs/api.md): POST /v1/devices returns a deviceKey
/// used as the Bearer token for later calls. Does nothing until PlayscribeAPIBaseURL is set.
enum PushRegistrar {
    struct Follow: Encodable { var gameId: String?; var igdbId: Int?; var notify: String }
    private struct Body: Encodable { var apnsToken: String; var environment: String; var follows: [Follow] }
    private struct Reply: Decodable { var deviceKey: String }

    static var baseURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "PlayscribeAPIBaseURL") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    static func register(token: String, follows: [Follow]) {
        guard let url = baseURL?.appending(path: "v1/devices") else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Body(apnsToken: token, environment: environment, follows: follows))
        Task {
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return }
            UserDefaults.standard.set(reply.deviceKey, forKey: "deviceKey")
        }
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
