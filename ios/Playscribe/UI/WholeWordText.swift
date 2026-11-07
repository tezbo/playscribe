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
    @State private var shownHeight: CGFloat = 0

    init(text: String, font: Font, lines: Int, color: Color? = nil) {
        self.text = text; self.font = font; self.lines = lines; self.color = color
    }

    var body: some View {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let variants = [text] + (words.count > 1 ? stride(from: words.count - 1, through: 1, by: -1).map { words.prefix($0).joined(separator: " ") + "\u{2026}" } : [])
        // The choice of variant is made against a height this view sets itself (lines x line height), never against
        // whatever a List cell or pager happens to propose, so the cut is the same in every pose. The outer frame then
        // trims to the height actually shown, so a short text leaves no gap.
        ViewThatFits(in: .vertical) {
            ForEach(variants, id: \.self) { v in
                Text(v).font(font).foregroundStyle(color ?? .primary).fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
            }
        }
        .frame(height: lineHeight > 0 ? (lineHeight * CGFloat(lines)).rounded(.up) + 1 : nil, alignment: .topLeading)
        .frame(height: lineHeight > 0 && shownHeight > 0 ? min(shownHeight, (lineHeight * CGFloat(lines)).rounded(.up) + 1) : nil, alignment: .topLeading)
        .clipped()
        .background(alignment: .topLeading) {
            Text("Ag").font(font).hidden().accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
