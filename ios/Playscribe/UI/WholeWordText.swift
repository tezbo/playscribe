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
    @State private var width: CGFloat = 0
    @State private var wordWidths: [Int: CGFloat] = [:]

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

    /// The whole text first, then one word fewer each time with "…" after the last whole word. Never a cut word.
    static func variants(of text: String) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return [text] + (words.count > 1 ? stride(from: words.count - 1, through: 1, by: -1).map { words.prefix($0).joined(separator: " ") + "\u{2026}" } : [])
    }

    var body: some View {
        let variants = Self.fittingVariants(of: text, wordWidths: wordWidths, available: width)
        let words = Self.words(of: text)
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
        .background(alignment: .topLeading) {
            Color.clear.frame(height: 0).frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
        .background(alignment: .topLeading) {
            // Each word on one line, so a word wider than the column can be told apart from one that merely wraps.
            ZStack(alignment: .topLeading) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                    Text(w).font(font).fixedSize().hidden().accessibilityHidden(true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { wordWidths[i] = $0 }
                }
            }
            .frame(width: 0, height: 0, alignment: .topLeading)
        }
        .onChange(of: text) { wordWidths = [:] }
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
