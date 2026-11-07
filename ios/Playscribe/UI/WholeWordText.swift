import SwiftUI

/// Text that, when it does not fit in `lines` lines, ends on a whole word followed by "…" (never a cut word, which
/// SwiftUI's own tail truncation can produce). Tries the whole text, then one word fewer each time. The line height is
/// measured from the same font at the current text size, so it holds at every Dynamic Type size.
struct WholeWordText: View {
    var text: String
    var font: Font
    var lines: Int
    var color: Color?
    @State private var lineHeight: CGFloat = 0

    /// The whole text first, then one word fewer each time with "…" after the last whole word. Never a cut word.
    static func variants(of text: String) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return [text] + (words.count > 1 ? stride(from: words.count - 1, through: 1, by: -1).map { words.prefix($0).joined(separator: " ") + "\u{2026}" } : [])
    }

    var body: some View {
        let variants = Self.variants(of: text)
        // The variant is chosen against a height this view sets itself (lines x line height), never against what a List
        // cell or pager proposes, so the cut is the same in every pose. The box is then as tall as the words shown, so a
        // one-line name leaves no gap below it (#357).
        let cap: CGFloat? = lineHeight > 0 ? (lineHeight * CGFloat(lines)).rounded(.up) + 1 : nil
        let fit = ViewThatFits(in: .vertical) {
            ForEach(variants, id: \.self) { v in
                Text(v).font(font).foregroundStyle(color ?? .primary).fixedSize(horizontal: false, vertical: true)
            }
        }
        HugHeight(cap: cap) { fit }
        .clipped()
        .background(alignment: .topLeading) {
            Text("Ag").font(font).hidden().accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Offers its child at most `cap` points of height and takes the size the child answers with (a plain flexible frame would
/// take the whole offer). Only meant for a single child.
private struct HugHeight: Layout {
    var cap: CGFloat?
    private func offer(_ p: ProposedViewSize) -> ProposedViewSize { ProposedViewSize(width: p.width, height: cap ?? p.height) }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(offer(proposal)) ?? .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: offer(ProposedViewSize(width: bounds.width, height: bounds.height)))
    }
}
