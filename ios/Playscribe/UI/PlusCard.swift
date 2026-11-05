import SwiftUI

/// PS Plus monthly games (0.5.0, r050-plus-card): this month's lineup in the Library, "Last chance" in its last
/// three days. Names and dates only. A game you track opens its page. Hidden when no month holds today.
struct PlusCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let (month, lastChance) = PlusLogic.visibleMonth(PlusStore.shared.months, cardOff: model.data.plusCardOff) {
            let claimBy = PlusLogic.claimByText(month)
            VStack(alignment: .leading, spacing: 8) {
                Text(lastChance ? "PS Plus: last chance" : "PS Plus this month").font(PlayscribeFont.title3)
                    .accessibilityAddTraits(.isHeader)
                Text("Claim by \(claimBy)").font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textSecondary)
                ForEach(Array(month.games.enumerated()), id: \.offset) { _, g in
                    if let id = g.gameId, model.entry(id) != nil {
                        Button { model.openGame(id) } label: {
                            HStack(spacing: 8) {
                                Text(g.name).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").foregroundStyle(PlayscribeColor.textSecondary).accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tappableFrame()
                        .accessibilityHint("Opens the game")
                    } else {
                        Text(g.name).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    }
                }
                .font(PlayscribeFont.subheadline)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ink2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plusCard")
        }
    }
}
