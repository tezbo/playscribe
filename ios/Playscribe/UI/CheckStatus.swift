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
    static func checkedStamp(_ d: Date) -> String { "\(d.dayMonth), \(d.formatted(date: .omitted, time: .shortened))" }

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
                Text(offline ? "Couldn't check. Offline" : "Couldn't check")
                RetryButton()
            case .notChecked:
                Text("Not checked yet")
                RetryButton()
            }
        }
        .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textSecondary)
    }
}

struct RetryButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button("Retry") { Task { await model.refreshFeed() } }
            .font(PlayscribeFont.subheadline.weight(.semibold))
            .foregroundStyle(PlayscribeColor.accent)
            .frame(minHeight: 44)
            .tappableFrame()
    }
}

/// A game with no notes never claims "No updates yet" when the check itself failed.
struct NoUpdatesLine: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch model.checkState {
            case .checked: Text("No updates yet.")
            case .failed, .notChecked: Text("Couldn't check yet.")
            }
            CheckedLine()
        }
        .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textSecondary)
    }
}

/// One line under the header: "Showing saved updates, you're offline", gone on success.
struct StaleHint: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if case .failed(let offline) = model.checkState {
            HStack(spacing: 8) {
                Image(systemName: offline ? "wifi.slash" : "exclamationmark.circle")
                Text(offline ? "Showing saved updates, you're offline" : "Showing saved updates")
                Spacer(minLength: 0)
                RetryButton()
            }
            .font(PlayscribeFont.footnote)
            .foregroundStyle(PlayscribeColor.textSecondary)
            .padding(.horizontal, 20)
            .accessibilityElement(children: .contain)
        }
    }
}
