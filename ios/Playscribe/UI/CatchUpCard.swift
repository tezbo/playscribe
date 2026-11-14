import SwiftUI

/// A6: "Since you last opened", at the top of the Library once per launch when updates arrived
/// since the last open. Updates older than 72 h are already read and never listed.
struct CatchUpCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let items = model.catchUpItems
        if !items.isEmpty {
            let games = Set(items.map(\.game.id)).count
            let summary = "\(items.count) update\(items.count == 1 ? "" : "s") across \(games) game\(games == 1 ? "" : "s")"
            VStack(alignment: .leading, spacing: 10) {
                Text("Since you last opened").font(PlayscribeFont.title3)
                    .accessibilityAddTraits(.isHeader)
                Text(summary).font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textSecondary)
                if let line = Self.digestLine(items.map(\.release)) {
                    Text(line).font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textSecondary)
                }
                if let top = items.lazy.compactMap({ $0.release.digest?.topNew }).first(where: { !$0.isEmpty }) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(top.prefix(3), id: \.self) { Text($0).font(PlayscribeFont.footnote).lineLimit(2) }
                    }
                }
                ForEach(items.prefix(3), id: \.release.id) { item in
                    Button { model.openGame(item.game.id, chapter: .updates, releaseID: item.release.id) } label: {
                        HStack(spacing: 12) {
                            CoverView(game: item.game, cornerRadius: 6).frame(width: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.game.name.gluingTrailingNumeral).font(PlayscribeFont.headline).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                                HStack(spacing: 8) {
                                    Text(item.release.displayName)
                                    if let l = item.release.ps4Label { Text(l).fontWeight(.semibold) }
                                    if let v = item.release.ps5Version { Text(v.keepingVersionsTogether).monospacedDigit() }
                                }
                                .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tappableFrame()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.game.name), \(item.release.displayName)")
                    .accessibilityAddTraits(.isButton)
                }
                Button("Mark all read") { model.markCatchUpRead() }
                    .font(PlayscribeFont.subheadline.weight(.semibold))
                    .foregroundStyle(PlayscribeColor.accent)
                    .frame(minHeight: 44)
                    .tappableFrame()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ink2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(summary)
        }
    }

    /// "12 new, 8 fixed, 3 balance changes" summed over the releases; nil when the feed has no digest.
    static func digestLine(_ releases: [Release]) -> String? {
        let d = releases.compactMap(\.digest)
        guard !d.isEmpty else { return nil }
        let parts = [(d.reduce(0) { $0 + $1.new }, "new"), (d.reduce(0) { $0 + $1.fixed }, "fixed"),
                     (d.reduce(0) { $0 + $1.balance }, "balance")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
