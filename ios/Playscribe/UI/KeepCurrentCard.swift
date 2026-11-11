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
        "A random code that our server makes for your phone. It is not linked to your name, email, Apple ID or phone, and it only lets you update or delete your own record.",
        "Once a week while you use the app, a tiny \"still here\" note, so the record can expire.",
    ]
    static let neverHeading = "What is never sent"
    static let neverBody = "Your name or email, your location, what you read or search, your Owned or Wishlist marks, photos, contacts or feedback you write."
    static let keptHeading = "How long it is kept"
    static let keptBody = "Up to 90 days after your last \"still here\" note. It is deleted straight away when you turn this off or reset the app, unless you also have alerts on. Then the games you follow stay on our server for your alerts until you turn alerts off too."
    static let turnOn = "Turn on"
    static let notNow = "Not now"
    static let cardVoiceOver = "Help keep your games up to date? \(Brand.name) can send the games you follow, and a random code, to our server. Details follow."
    static let turnOnVoiceOver = "Turn on, sends the games you follow"
    static let notNowVoiceOver = "Not now, sends nothing"

    // The Settings row.
    static let settingsTitle = "Help keep my games up to date"
    // Trimmed by Iris (11 Nov) to 45 words so it fits five lines at the largest size; both facts kept.
    static let settingsCaption = "Sends the games you follow, and a random code, to our server so it checks them every hour. Nothing else is sent. Off: nothing is sent and updates can take up to 14 hours. With alerts on, those games stay on our server for alerts."
    static let settingsHint = "Turn off to stop hourly checks. Your record is deleted unless alerts are on"
    static let settingsOnVoiceOver = "Sends the games you follow to our server."
    static let whatIsSent = "What is sent"
    /// The store line and the Settings footer when on.
    static let shortLine = "Only the games you follow and a random code. Not linked to you. Kept up to 90 days. Deleted when you turn this and alerts off."

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
struct KeepCurrentCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func answer(_ on: Bool) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth) { if on { model.setKeepCurrent(true) } else { model.dismissKeepCurrentCard() } }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath").font(PlayscribeFont.title2).foregroundStyle(PlayscribeColor.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(KeepCurrentCopy.cardTitle).font(PlayscribeFont.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(KeepCurrentCopy.cardVoiceOver)
                    .accessibilityAddTraits(.isHeader)
                Text(KeepCurrentCopy.cardIntro)
                    .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The three short sections stay in the card at every size: the Library scrolls, nothing is dropped from view or
                // from VoiceOver, and no sheet is needed (Tabletop keeps the lower half as the only stage for controls).
                KeepCurrentList(compact: true)
                // Accessibility sizes stack the buttons full width (N-1 rule).
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) { buttons }.padding(.top, 6)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { buttons }
                        VStack(alignment: .leading, spacing: 8) { buttons }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.ink2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if abs(v.translation.width) > 60 { answer(false) }
        })
        .accessibilityAction(named: KeepCurrentCopy.notNow) { answer(false) }
        .accessibilityIdentifier("keepCurrentCard")
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .leading)))
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

/// The "What is sent", "What is never sent" and "How long it is kept" sections: compact in the card, full on the details page.
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

/// "What is sent" from Settings and the card: the same list as the card, in full, plus the short line.
struct KeepCurrentDetailsView: View {
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
        .background(Color.ink0)
        .navigationTitle(KeepCurrentCopy.whatIsSent)
        .navigationBarTitleDisplayMode(.inline)
    }
}
