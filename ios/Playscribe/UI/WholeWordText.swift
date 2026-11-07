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

    static func words(of text: String) -> [String] { text.split(separator: " ", omittingEmptySubsequences: true).map(String.init) }

    /// The variants whose every kept word fits `available` points on one line. A word wider than the column is wrapped by
    /// character, which leaves a fragment (or a lone comma) at the start of a line, so a variant that keeps one is dropped
    /// and the cut lands before that word. Always keeps at least the shortest variant. Unknown widths keep everything.
    static func fittingVariants(of text: String, wordWidths: [Int: CGFloat], available: CGFloat) -> [String] {
        let all = variants(of: text)
        let n = words(of: text).count
        guard available > 0, n > 1, wordWidths.count == n else { return all }
        var out: [String] = []
        for (i, v) in all.enumerated() {
            let kept = n - i
            let widest = (0..<kept).map { wordWidths[$0] ?? 0 }.max() ?? 0
            if widest <= available || i == all.count - 1 { out.append(v) }
        }
        return out
    }

    /// `kept` without trailing , ; : . so the ellipsis follows the word ("Rebalancing…", never "Rebalancing,…").
    static func trimmed(_ kept: String) -> String {
        var t = Substring(kept)
        while let last = t.last, ",;:.".contains(last), t.count > 1 { t = t.dropLast() }
        return String(t)
    }

    /// The whole text first, then one word fewer each time with "…" after the last whole word. Never a cut word.
    static func variants(of text: String) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return [text] + (words.count > 1 ? stride(from: words.count - 1, through: 1, by: -1).map { trimmed(words.prefix($0).joined(separator: " ")) + "\u{2026}" } : [])
    }

    var body: some View {
        let all = Self.variants(of: text)
        let words = Self.words(of: text)
        // The variant is chosen against a height this view sets itself (lines x line height), never against what a List
        // cell or pager proposes, so the cut is the same in every pose. The box is then as tall as the words shown, so a
        // one-line name leaves no gap below it (#357).
        let cap: CGFloat? = lineHeight > 0 ? (lineHeight * CGFloat(lines)).rounded(.up) + 1 : nil
        // The choice is made inside PickVariant, against the width it is really offered (the column), and the width of
        // every word measured on one line. An earlier version read the hugged width of its own text back through state,
        // which was narrower than the column, so a word that no longer fitted could still be kept and a comma was left
        // alone at the start of a line (r061).
        PickVariant(text: text, variantCount: all.count, cap: cap) {
            ForEach(Array(all.enumerated()), id: \.offset) { _, v in
                Text(v).font(font).foregroundStyle(color ?? .primary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                Text(w).font(font).fixedSize()
            }
        }
        .clipped()
        .background(alignment: .topLeading) {
            Text("Ag").font(font).hidden().accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Shows exactly one of its first `variantCount` children: the first whose words each fit the offered width on one line
/// and whose height fits `cap`. The remaining children are the words of `text`, only measured (placed off to the side and
/// clipped by the parent). Falls back to the shortest variant, never blank. Takes the height of the child it shows.
private struct PickVariant: Layout {
    var text: String
    var variantCount: Int
    var cap: CGFloat?

    private func width(_ p: ProposedViewSize) -> CGFloat? { p.width.flatMap { $0.isFinite ? $0 : nil } }

    private func choose(_ subviews: Subviews, width: CGFloat?) -> Int {
        guard variantCount > 0, subviews.count >= variantCount else { return 0 }
        var start = 0
        if let width {
            var widths: [Int: CGFloat] = [:]
            for i in 0..<(subviews.count - variantCount) { widths[i] = subviews[variantCount + i].sizeThatFits(.unspecified).width }
            start = variantCount - WholeWordText.fittingVariants(of: text, wordWidths: widths, available: width).count
        }
        for i in start..<variantCount {
            let h = subviews[i].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            if cap == nil || h <= cap! { return i }
        }
        return variantCount - 1
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let w = width(proposal)
        let size = subviews[choose(subviews, width: w)].sizeThatFits(ProposedViewSize(width: w, height: nil))
        return CGSize(width: size.width, height: cap.map { min(size.height, $0) } ?? size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let chosen = choose(subviews, width: bounds.width)
        for (i, s) in subviews.enumerated() {
            let at = i == chosen ? bounds.origin : CGPoint(x: bounds.minX - 100_000, y: bounds.minY)
            s.place(at: at, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}
