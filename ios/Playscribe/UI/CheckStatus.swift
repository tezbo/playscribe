import SwiftUI

/// Offline, empty and error states 2 and 3 (r050-offline-states): the Checked line says only what
/// happened, and a stale game page says so.
enum CheckState: Equatable {
    case checked(Date)
    case failed(offline: Bool)
    case notChecked
}

extension AppModel {
    var checkState: CheckState {
        switch feedStatus {
        case .updated(let d): .checked(d)
        case .offline: .failed(offline: true)
        case .failed: .failed(offline: false)
        case .idle, .refreshing:
            FeedClient.loadCache().map { .checked($0.updatedAt) } ?? .notChecked
        }
    }

    /// "3 Nov, 14:20"
    static func checkedStamp(_ d: Date) -> String { "\(d.localDayMonth), \(d.formatted(date: .omitted, time: .shortened))" }

    /// Retry: check again and say the result aloud, since the line changes silently (a11y pass).
    func retryCheck() async {
        await refreshFeed()
        let text: String
        switch checkState {
        case .checked(let d): text = "Checked \(Self.checkedStamp(d))"
        case .failed(let offline): text = offline ? "Couldn’t check. Offline" : "Couldn’t check"
        case .notChecked: text = "Not checked yet"
        }
        AccessibilityNotification.Announcement(text).post()
    }

    /// More > Check for updates (Terry, 21 Nov: it gave no feedback). A toast says it is checking, then what happened:
    /// new PS5 updates for this game ("Up to date" would read as the player's PS5 being current; Iris), no new updates with the Checked time, or why it couldn't check. Toasts are announced.
    func checkForUpdates(_ gameID: String) async {
        show(Toast(text: "Checking for updates…", seconds: 30))
        let before = Set(releases(gameID).filter(\.isPS5Listed).map(\.id))
        await refreshFeed()
        await refreshHistories([gameID])
        let added = releases(gameID).filter { $0.isPS5Listed && !before.contains($0.id) }.count
        // About 4 s, longer at accessibility sizes (Iris).
        let seconds: Double = UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory ? 7 : 4
        show(Toast(text: Self.checkResult(checkState, newUpdates: added, at: .now), seconds: seconds))
        // Tabletop's News page is view only, so this is also its retry.
        await NewsStore.shared.load(gameID: gameID, igdbID: game(gameID)?.igdbID)
    }

    /// "2 new updates", "No new updates. Checked 21 Nov, 6:51 am", "Couldn’t check. You’re offline" or "Couldn’t check. Try again later".
    /// "22 Nov, 4:32 am" never splits across lines; the toast breaks after "No new updates." or "Checked" (Iris, AX5).
    static func boundStamp(_ d: Date) -> String { checkedStamp(d).replacingOccurrences(of: " ", with: "\u{00A0}") }

    /// The stamp is when the player checked (`at`), not when the feed was last built: a 4:32 am feed time read as stale
    /// after a 7:15 am check (Mac, a1f48b94).
    static func checkResult(_ state: CheckState, newUpdates: Int, at now: Date) -> String {
        switch state {
        case .checked:
            newUpdates > 0 ? "\(newUpdates) new update\(newUpdates == 1 ? "" : "s")" : "No new updates. Checked \(boundStamp(now))"
        case .failed(let offline): offline ? "Couldn’t check. You’re offline" : "Couldn’t check. Try again later"
        case .notChecked: "Couldn’t check. Try again later"
        }
    }

    var feedIsStale: Bool {
        if case .failed = checkState { return true }
        return false
    }
}

/// "Checked 3 Nov, 14:20", "Couldn't check. Offline" or "Not checked yet", with Retry when it failed.
struct CheckedLine: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 8) {
            switch model.checkState {
            case .checked(let d):
                Text("Checked \(AppModel.checkedStamp(d))")
            case .failed(let offline):
                Text(offline ? "Couldn’t check. Offline" : "Couldn’t check")
                RetryButton()
            case .notChecked:
                Text("Not checked yet")
                RetryButton()
            }
        }
        .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeRole.textSecondary)
    }
}

struct RetryButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { Task { await model.retryCheck() } } label: { Text("Retry").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
            .font(PlayscribeFont.subheadline.weight(.semibold))
            .foregroundStyle(PlayscribeRole.action)
            .tappableFrame()
    }
}

/// A game with no notes never claims "No updates yet" when the check itself failed, nor when the feed does not follow the game
/// at all (it is outside the tracked set): then it says so, and shows no Checked line, since nothing was checked for it.
struct NoUpdatesLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var gameID: String
    /// The "checked, nothing yet" line. Only a game in the library promises to tell the reader (Tabletop's lower half, Iris): a game
    /// that is only being browsed has no alert to promise, so it says the plain fact.
    static func checkedCopy(tabletop: Bool, inLibrary: Bool) -> String {
        tabletop && inLibrary ? "No updates yet. We’ll tell you when the first one lands." : "No updates yet."
    }
    var body: some View {
        if model.feedTracksGame(gameID) {
            VStack(alignment: .leading, spacing: 2) {
                switch model.checkState {
                // Tabletop's lower half is the only place a reader looks for why there is nothing (Iris, bug-tabletop-game-details-missing).
                case .checked: Text(Self.checkedCopy(tabletop: duo.pose == .tabletop, inLibrary: model.entry(gameID) != nil))
                case .failed, .notChecked: Text("Couldn’t check yet.")
                }
                CheckedLine()
            }
            .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeRole.textSecondary)
        } else {
            Text("We don’t track this game’s updates yet.")
                .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeRole.textSecondary)
        }
    }
}

/// One line under the header: "Showing saved updates, you're offline", gone on success.
struct StaleHint: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if case .failed(let offline) = model.checkState {
            HStack(spacing: 8) {
                Image(systemName: offline ? "wifi.slash" : "exclamationmark.circle")
                Text(offline ? "Showing saved updates, you’re offline" : "Showing saved updates")
                Spacer(minLength: 0)
                RetryButton()
            }
            .font(PlayscribeFont.footnote)
            .foregroundStyle(PlayscribeRole.textSecondary)
            .padding(.horizontal, 20)
            .accessibilityElement(children: .contain)
        }
    }
}

/// Offline states 5 and 6: nothing released lately. One calm card in the hero slot, never a gap.
struct CaughtUpCard: View {
    @Environment(AppModel.self) private var model

    private var lastUpdate: Date? {
        model.data.collection.flatMap { model.ps5Releases($0.gameID) }
            .filter { $0.ps5State == .onPS5 }.map(\.ps5Date).max()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You’re all caught up").font(PlayscribeFont.headline)
            Text(lastUpdate.map { "Last update \($0.dayMonth)" } ?? "Nothing new in 90 days")
                .font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PlayscribeRole.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
