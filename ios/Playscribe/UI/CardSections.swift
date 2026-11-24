import SwiftUI

/// Grouped cards that keep an edge when Reduce Transparency or Increase Contrast is on (s-06-control-border; Iris on #557).
/// Light under Reduce Transparency drew white cards straight onto the sheet's grey with no outline (1.12:1, Mac b2400b3b), so
/// in that mode every card gets a 1 pt outline in the card edge role: #857A68 in light (the control border), #6F6A7C in dark,
/// where the card was 1.22:1 on the sheet (Iris on #557). Outside that mode the content is returned as it was, in both schemes.
///
/// Wrap a Form's or List's sections: `Form { CardSections { Section { … } … } }`. It reads the sections and rows itself, so
/// conditional rows and `ForEach` rows are counted, and the first and last row of each card round off its outline.
struct CardSections<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.qaSolid) private var qaSolid
    /// A fill for every row, where the screen sets its own cards (Settings in light: surface cards on the bg cream, Iris). Nil keeps
    /// the system cell fill.
    var rowFill: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        if reduceTransparency || contrast == .increased || qaSolid {
            ForEach(sections: content) { section in
                Section {
                    Group(subviews: section.content) { rows in
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            row.listRowBackground(CardRowBackground(first: i == 0, last: i == rows.count - 1))
                        }
                    }
                } header: {
                    section.header
                } footer: {
                    section.footer
                }
            }
        } else if let rowFill {
            ForEach(sections: content) { section in
                Section {
                    Group(subviews: section.content) { rows in
                        ForEach(rows) { row in row.listRowBackground(rowFill) }
                    }
                } header: {
                    section.header
                } footer: {
                    section.footer
                }
            }
        } else {
            content
        }
    }
}

/// One row's slice of a card: the system cell fill, and the card outline's sides, plus its top on the first row and its
/// bottom on the last. Middle rows draw sides only, so rows meet without a doubled line.
struct CardRowBackground: View {
    var first: Bool
    var last: Bool
    /// At least the system's own card corner, so the system's corner clip never cuts the outline.
    static let radius: CGFloat = 28

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            CardRowEdge(top: first, bottom: last, radius: Self.radius)
                .stroke(PlayscribeRole.cardEdge, lineWidth: 1)
                .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// The outline path for one row: a rounded rectangle inset half a point so the 1 pt stroke sits inside the row, pushed 2 pt
/// past the row's top or bottom where that edge belongs to a neighbouring row (the overhang is clipped away).
nonisolated struct CardRowEdge: Shape {
    var top: Bool
    var bottom: Bool
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var r = rect.insetBy(dx: 0.5, dy: 0.5)
        if !top { r.origin.y -= 2; r.size.height += 2 }
        if !bottom { r.size.height += 2 }
        let shape = UnevenRoundedRectangle(topLeadingRadius: top ? radius : 0, bottomLeadingRadius: bottom ? radius : 0,
                                           bottomTrailingRadius: bottom ? radius : 0, topTrailingRadius: top ? radius : 0,
                                           style: .continuous)
        return shape.path(in: r)
    }
}
