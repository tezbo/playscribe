import SwiftUI

/// s-06 (0.5.6, spec.md "Game page", s3.png): what one row of a game's update list says, patch first. Line one is the patch
/// name (the studio's display name, "Patch 1.7.3"), line two the headline ("Fixes and tuning"), line three the date and the
/// PS5 line ("Out on PS5"). A release with no patch name leads with its headline alone, so a row is never blank. No version
/// number appears here (a PC number is never shown as a PS5 one), and nothing is joined with a dot.
struct UpdateRowText: Equatable {
    var title: String
    var headline: String?
    var date: String
    var status: String?

    init(_ r: Release) {
        let name = r.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        // A PS5 row reads the PS5 headline, which drops a PC-only headline (docs/ps5-patch-data.md).
        let raw = (r.isPS5Listed ? r.ps5Headline : r.headline)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = raw.flatMap { $0.isEmpty ? nil : $0 }
        if name.isEmpty {
            title = head ?? "Update"
            headline = nil
        } else {
            title = name
            headline = head.flatMap { $0.caseInsensitiveCompare(name) == .orderedSame ? nil : $0 }
        }
        date = (r.isPS5Listed ? r.ps5Date : r.latestDate).dayMonthOrYear
        status = Self.status(r)
    }

    /// The PS5 line, from the PS5 row's state only (spec acceptance 3). Pending is never shown to the player.
    static func status(_ r: Release) -> String? {
        switch r.ps5State {
        case .onPS5: "Out on PS5"
        case .announced: "Announced for PS5"
        case .reported: "Reported on PS5"
        case .notPlanned: "Not planned for PS5"
        case .pending: nil
        }
    }
}

/// One row of a game's update list (s3.png). "New" in accent text, not colour alone, at the end of the patch name's line
/// while unread; a hairline under each row. At accessibility sizes the date and PS5 line stack when they do not share a
/// line, and every line ends on a whole word.
struct UpdateRowLabel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var release: Release
    var unread: Bool
    var selected: Bool

    static let nameFont = Font.custom("InstrumentSans-Bold", size: 17, relativeTo: .headline)
    static let newFont = Font.custom("InstrumentSans-Bold", size: 13, relativeTo: .footnote)

    var body: some View {
        let t = UpdateRowText(release)
        let ax = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WholeWordText(text: t.title, font: Self.nameFont, lines: ax ? 3 : 2, color: PlayscribeColor.textPrimary)
                Spacer(minLength: 0)
                if unread {
                    Text("New").font(Self.newFont).foregroundStyle(PlayscribeColor.accent)
                        .fixedSize()
                }
            }
            if let h = t.headline {
                WholeWordText(text: h, font: PlayscribeFont.subheadline, lines: ax ? 3 : 2, color: PlayscribeColor.textPrimary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(t.date).fixedSize()
                    Spacer(minLength: 0)
                    if let s = t.status { Text(s).fixedSize() }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.date)
                    if let s = t.status { Text(s).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .font(PlayscribeFont.caption).foregroundStyle(PlayscribeColor.textSecondary)
            // The chips that are not the PS5 line stay with the row (never drop chips): PS4 update, Simulated.
            if release.ps4Label != nil || (release.simulated == true && release.ps5State == .onPS5) {
                FlowLayout(spacing: 6) {
                    if let l = release.ps4Label { Tag(text: l, tint: .secondary) }
                    if release.simulated == true, release.ps5State == .onPS5 { Tag(text: "Simulated", tint: .simulated) }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(selected ? PlayscribeColor.ink700 : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle().fill(PlayscribeColor.ink700).frame(height: 1).padding(.horizontal, 10).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(t, unread: unread, release: release))
    }

    /// VoiceOver reads the row in its visual order: patch, New, headline, date, PS5 line.
    static func spoken(_ t: UpdateRowText, unread: Bool, release: Release) -> String {
        var parts = [t.title]
        if unread { parts.append("New") }
        if let h = t.headline { parts.append(h) }
        parts.append(t.date)
        if let s = t.status { parts.append(s) }
        if let l = release.ps4Label { parts.append(l) }
        return parts.joined(separator: ", ")
    }
}
