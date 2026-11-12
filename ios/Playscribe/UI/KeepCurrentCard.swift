import SwiftUI

/// Every word the app shows about "Help keep my games up to date" (0.5.4), in one place. Written by Ezra from the design
/// note's "What leaves the phone" list (project files, design/follow-list-copy-final-draft.md); each line maps to a line in
/// that list, so a change to what is sent changes this file and the list together. N-9 in docs/ux-acceptance.md.
enum KeepCurrentCopy {
    // The one-time card.
    static let cardTitle = "Help keep your games up to date?"
    static let cardIntro = "\(Brand.name) can tell our server which games you follow, so it checks those games every hour. Without this, new updates for them can take up to about 14 hours to show up."
    static let sentHeading = "What is sent"
    static let sentItems = [
        "The games you follow.",
        "A random code that our server makes for your device. It is not linked to you, and it only lets you update or delete your own record.",
        "Once a week, a short check-in, so we can remove records from devices that stopped using the app.",
    ]
    static let neverHeading = "What is never sent"
    static let neverBody = "Your location, what you read or search, your Owned or Wishlist marks, photos, contacts or feedback you write."
    // Ezra v2 (12 Nov, design/follow-list-copy-v2-before-after.md), from Quinn's capture: every request also carries these.
    static let connectionHeading = "What every connection carries"
    static let connectionBody = "Like any app that connects to a server, the request also carries your IP address, the app and iOS version, and your language setting. We do not store them."
    static let keptHeading = "How long it is kept"
    // Ezra v2 (12 Nov): no "reset the app", which only internal builds have. v3 (12 Nov): no "still here" (Terry did not follow it).
    static let keptBody = "Until you turn this off. If you stop using the app, it is removed within 90 days. Deleting the app and installing it again also removes it. If you also have alerts on, the games you follow stay on our server for your alerts until you turn alerts off too."
    static let turnOn = "Turn on"
    static let notNow = "Not now"
    static let cardVoiceOver = "Help keep your games up to date? \(Brand.name) can send the games you follow, and a random code, to our server. Details follow."
    static let turnOnVoiceOver = "Turn on, sends the games you follow"
    static let notNowVoiceOver = "Not now, sends nothing"

    // The Settings row.
    static let settingsTitle = "Help keep my games up to date"
    // Trimmed by Iris (11 Nov) to 45 words so it fits five lines at the largest size; both facts kept.
    // Ezra v2 (12 Nov): "Nothing else is sent" became "Only these are stored" (every request carries IP, app and iOS version
    // and language); same word count. Terry approved the earlier wording; Ezra brings v2 to Terry before the tag.
    static let settingsCaption = "Sends the games you follow, and a random code, to our server so it checks them every hour. Only these are stored. If not enabled, nothing is sent and updates can take up to 14 hours."
    static let settingsHint = "Turn off to stop hourly checks. Your record is deleted unless alerts are on"
    static let settingsOnVoiceOver = "Sends the games you follow to our server."
    static let whatIsSent = "What is sent"
    /// The store line and the Settings footer when on.
    static let shortLine = "Only the games you follow and a random code. Not linked to you. Removed within 90 days if you stop using the app, or when you turn this and alerts off."

    /// "Last sent: today" or "Last sent: 3 days ago"; nil before anything was sent (the record is made at the first follow).
    static func lastSent(_ date: Date?, now: Date = .now) -> String? {
        guard let date else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Last sent: today"
        case 1: return "Last sent: yesterday"
        default: return "Last sent: \(days) days ago"
        }
    }
}

/// N-9: the one-time ask, in context, once a game is in the Library. Turn on sends the list from the next save; Not now or a
/// swipe sends nothing, ever, until the switch is turned on in Settings. Same frame and stacking rules as the alerts card (N-1).
///
/// Compact in every pose (Iris, #455 at f55062a): the four lists inline took about 60% of a Closed screen (BOOK BALANCE: no
/// module over 25% of a page) and cut off the buttons in Book and Tabletop. Title, the short line, "What is sent", then the two
/// buttons. "What is sent" opens the full wording (the same lists, unchanged) in a sheet before the person decides, so the
/// explicit disclosure is one tap from the choice, in the app.
struct KeepCurrentCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func answer(_ on: Bool) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth) { if on { model.setKeepCurrent(true) } else { model.dismissKeepCurrentCard() } }
    }

    var body: some View {
        let ax = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 8) {
            // Accessibility sizes drop the icon, so the text and buttons use the card's full width (Iris: no icon gutter).
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if !ax {
                    Image(systemName: "arrow.triangle.2.circlepath").font(PlayscribeFont.headline).foregroundStyle(PlayscribeColor.accent)
                        .accessibilityHidden(true)
                }
                Text(KeepCurrentCopy.cardTitle).font(PlayscribeFont.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(KeepCurrentCopy.cardVoiceOver)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(KeepCurrentCopy.shortLine)
                .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if ax {
                // Accessibility sizes stack everything full width (N-1 rule): the link first, then the two buttons.
                whatIsSent
                VStack(alignment: .leading, spacing: 12) { buttons }.padding(.top, 2)
            } else {
                // One row where it fits (Tabletop, Open, Book's page), so the card stays about 150 pt tall.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { buttons; Spacer(minLength: 8); whatIsSent }
                    VStack(alignment: .leading, spacing: 6) { whatIsSent; HStack(spacing: 12) { buttons } }
                    VStack(alignment: .leading, spacing: 8) { whatIsSent; buttons }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.ink2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if abs(v.translation.width) > 60 { answer(false) }
        })
        .accessibilityAction(named: KeepCurrentCopy.notNow) { answer(false) }
        .accessibilityAction(named: KeepCurrentCopy.whatIsSent) { model.keepCurrentDetailsOpen = true }
        .accessibilityIdentifier("keepCurrentCard")
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .leading)))
    }

    private var whatIsSent: some View {
        Button { model.keepCurrentDetailsOpen = true } label: {
            HStack(spacing: 4) {
                Text(KeepCurrentCopy.whatIsSent)
                Image(systemName: "chevron.right").font(PlayscribeFont.footnote.weight(.semibold)).accessibilityHidden(true)
            }
            .font(PlayscribeFont.subheadline.weight(.semibold))
            .foregroundStyle(PlayscribeColor.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows what is sent, what is never sent and how long it is kept")
        .accessibilityIdentifier("keepCurrentWhatIsSentCard")
        .tappableFrame()
    }

    @ViewBuilder private var buttons: some View {
        Button { answer(true) } label: {
            Text(KeepCurrentCopy.turnOn).frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(typeSize.isAccessibilitySize ? .roundedRectangle(radius: 14) : .capsule)
        .foregroundStyle(PlayscribeColor.onAccent)
        .accessibilityLabel(KeepCurrentCopy.turnOnVoiceOver)
        .accessibilityIdentifier("keepCurrentTurnOn")
        .hitTarget()
        .tappableFrame()
        Button { answer(false) } label: {
            Text(KeepCurrentCopy.notNow).frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
        }
        .buttonStyle(.bordered).buttonBorderShape(typeSize.isAccessibilitySize ? .roundedRectangle(radius: 14) : .capsule)
        .accessibilityLabel(KeepCurrentCopy.notNowVoiceOver)
        .accessibilityIdentifier("keepCurrentNotNow")
        .hitTarget()
        .tappableFrame()
    }
}

/// The card's "What is sent": the full wording in a sheet (a system sheet, or Tabletop's lower-half panel), with Done.
struct KeepCurrentDetailsSheet: View {
    @Environment(\.panelClose) private var panelClose
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Iris (Closed AX5 at cb12f54): an opaque header, so scrolled text never shows under the two-line title, and at
            // AX3 and above Done sits level with the title's first line, not halfway down it.
            HStack(alignment: typeSize >= .accessibility3 ? .top : .center) {
                Text(KeepCurrentCopy.whatIsSent).font(PlayscribeFont.title3).accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { if let panelClose { panelClose() } else { systemDismiss() } } label: {
                    Text("Done").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityHint("Closes this and goes back to the choice").accessibilityIdentifier("close").tappableFrame()
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
            .background(Color.ink0)
            .zIndex(1)
            KeepCurrentDetailsContent()
                .clipped()
        }
        .padding(.top, 8)
        .background(Color.ink0)
        .accessibilityIdentifier("keepCurrentDetails")
    }
}

/// The "What is sent", "What is never sent" and "How long it is kept" sections, in full in the card's sheet and Settings.
struct KeepCurrentList: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            section(KeepCurrentCopy.sentHeading) {
                ForEach(KeepCurrentCopy.sentItems, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2022}").accessibilityHidden(true)
                        Text(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            section(KeepCurrentCopy.neverHeading) { Text(KeepCurrentCopy.neverBody).fixedSize(horizontal: false, vertical: true) }
            section(KeepCurrentCopy.connectionHeading) { Text(KeepCurrentCopy.connectionBody).fixedSize(horizontal: false, vertical: true) }
            section(KeepCurrentCopy.keptHeading) { Text(KeepCurrentCopy.keptBody).fixedSize(horizontal: false, vertical: true) }
        }
        .font(compact ? PlayscribeFont.footnote : PlayscribeFont.body)
        .foregroundStyle(compact ? PlayscribeColor.textSecondary : PlayscribeColor.textPrimary)
    }

    @ViewBuilder private func section<Body: View>(_ heading: String, @ViewBuilder body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading).font(compact ? PlayscribeFont.footnote.weight(.semibold) : PlayscribeFont.headline)
                .foregroundStyle(PlayscribeColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            body()
        }
    }
}

/// "What is sent" from Settings: the same wording as the card's sheet.
struct KeepCurrentDetailsView: View {
    var body: some View {
        KeepCurrentDetailsContent()
            .background(Color.ink0)
            .navigationTitle(KeepCurrentCopy.whatIsSent)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The full wording: what it does, what is sent, what is never sent, how long it is kept, and the short line.
struct KeepCurrentDetailsContent: View {
    /// Mac at d956c87 (Book and Tabletop AX5): a line cut at the scroll edge showed as stray glyph halves under the sheet's
    /// title. Once scrolled, the top edge is opaque for about half a line and fades over the rest, so a cut line is hidden or
    /// faded, never sliced; a hairline marks the edge. Scales with the body text, so it covers a line at every size.
    @ScaledMetric(relativeTo: .body) private var edgeFade: CGFloat = 30
    @State private var scrolled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(KeepCurrentCopy.cardIntro).font(PlayscribeFont.body).fixedSize(horizontal: false, vertical: true)
                KeepCurrentList()
                Text(KeepCurrentCopy.shortLine).font(PlayscribeFont.footnote).foregroundStyle(PlayscribeColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, now in scrolled = now }
        .overlay(alignment: .top) {
            if scrolled {
                VStack(spacing: 0) {
                    Rectangle().fill(PlayscribeColor.textSecondary.opacity(0.25)).frame(height: 0.5)
                    LinearGradient(stops: [.init(color: Color.ink0, location: 0), .init(color: Color.ink0, location: 0.5),
                                           .init(color: Color.ink0.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: edgeFade)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
