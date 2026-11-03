import SwiftUI
import UserNotifications

/// Follow a known issue (0.5.0 item 19): a line the feed lists under a game's `issues[]` gets a
/// Follow button; followed issues are listed at the top of All updates and alert once when a
/// later update lists them as fixed.
struct KnownIssue: Codable, Hashable, Identifiable {
    var id: String
    var text: String
    var status: String
    var firstReleaseId: String?
    var addressedBy: String?
    var addressedAt: Date?
    var isAddressed: Bool { status == "addressed" }
}

extension AppModel {
    private static func normalised(_ s: String) -> String { PS5Index.fold(LinkedText.clean(s)) }

    /// The feed issue behind a notes line, matched on normalised text.
    func knownIssue(for item: NoteItem, in gameID: String) -> KnownIssue? {
        let key = Self.normalised(item.text)
        guard !key.isEmpty else { return nil }
        return gameIssues[gameID]?.first { Self.normalised($0.text) == key }
    }

    func isFollowing(_ issue: KnownIssue) -> Bool { data.followedIssues?.contains(issue.id) == true }

    func toggleFollow(_ issue: KnownIssue) {
        var set = data.followedIssues ?? []
        let wasFollowing = set.contains(issue.id)
        if wasFollowing { set.remove(issue.id) } else { set.insert(issue.id) }
        data.followedIssues = set
        show(Toast(text: wasFollowing ? "Stopped following" : "Following this issue"))
    }

    func followedIssues(_ gameID: String) -> [KnownIssue] {
        (gameIssues[gameID] ?? []).filter(isFollowing)
    }

    func fixedInName(_ issue: KnownIssue, gameID: String) -> String? {
        guard let id = issue.addressedBy else { return nil }
        return releases(gameID).first { $0.id == id }.map { $0.ps5Version ?? $0.displayName }
    }

    /// One alert per followed issue, when it was fixed within the last 72 hours.
    func alertAddressedIssues() {
        let cutoff = Date.now.addingTimeInterval(-72 * 3600)
        var alerted = data.alertedIssues ?? []
        for (gameID, issues) in gameIssues {
            for i in issues where i.isAddressed && isFollowing(i) && !alerted.contains(i.id) {
                alerted.insert(i.id)
                guard let at = i.addressedAt, at > cutoff, notifyLevel(gameID) != .off, !data.pauseAll else { continue }
                NotificationService.shared.issueFixed(id: i.id, game: game(gameID)?.name ?? "", text: i.text,
                                                      version: fixedInName(i, gameID: gameID))
            }
        }
        data.alertedIssues = alerted
    }
}

struct FollowIssueButton: View {
    @Environment(AppModel.self) private var model
    var issue: KnownIssue
    var body: some View {
        let on = model.isFollowing(issue)
        if !issue.isAddressed {
            Button(on ? "Following" : "Follow") { model.toggleFollow(issue) }
                .font(PlayscribeFont.footnote.weight(.semibold))
                .foregroundStyle(on ? Color.secondary : PlayscribeColor.accent)
                .frame(minWidth: 44, minHeight: 44)
                .tappableFrame()
                .accessibilityLabel(on ? "Following this issue" : "Follow this issue")
                .accessibilityHint(on ? "Double tap to stop following" : "Alerts you when an update fixes it")
        }
    }
}

/// The "Following" list at the top of a game's All updates.
struct FollowingList: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        let list = model.followedIssues(gameID)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Following")
                ForEach(list) { issue in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LinkedText.clean(issue.text)).font(PlayscribeFont.subheadline).lineLimit(3)
                            Text(issue.isAddressed ? "Fixed in \(model.fixedInName(issue, gameID: gameID) ?? "a later update")" : "Not fixed yet")
                                .font(PlayscribeFont.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("Unfollow") { model.toggleFollow(issue) }
                            .font(PlayscribeFont.footnote.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
                            .frame(minHeight: 44).tappableFrame()
                    }
                }
            }
        }
    }
}

extension NotificationService {
    func issueFixed(id: String, game: String, text: String, version: String?) {
        let c = UNMutableNotificationContent()
        c.title = game
        c.body = "Fixed in \(version ?? "a new update"): \(LinkedText.clean(text))"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "issue-\(id)", content: c, trigger: nil))
    }
}
