import SwiftUI

/// R-7 (0.5.6 redesign, Card C; spec.md "Game page", s3.png, poses-g1.png): the game page's section bar.
/// - Up to AX2: text tabs, 48 pt tall, 14 pt semibold; the current tab bold with a 3 pt underline in the action colour, and a
///   hairline under the bar. Tabs never turn into the picker: 10 pt padding, else 6 pt, else they scroll sideways with
///   faded edges (design sign, 13 Nov).
/// - AX3 and up: one picker, 76 pt tall, showing the current section on one line with a chevron; it lists all five, the
///   current one ticked. VoiceOver reads "What's new, section picker, 1 of 5".
/// - Book: the same sections as a table of contents on the left page, one 48 pt row each.
/// Switching a section adds nothing to Back (Card D): it only changes `nav.chapter`.
struct SectionBar: View {
    enum Style { case bar, contents }

    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    var gameID: String
    var style: Style = .bar

    var body: some View {
        let sections = model.chapters(gameID)
        let current = model.section(gameID)
        Group {
            switch style {
            case .contents: contents(sections, current)
            case .bar:
                // Design sign (13 Nov): tabs up to AX2, the picker only from AX3. Tabs try 10 pt padding, then 6 pt, then
                // scroll sideways with faded edges, so five sections in a Closed column stay tabs at standard sizes.
                if typeSize >= .accessibility3 {
                    picker(sections, current)
                } else {
                    ViewThatFits(in: .horizontal) {
                        tabRow(sections, current, padding: 10).fixedSize(horizontal: true, vertical: false)
                        tabRow(sections, current, padding: 6).fixedSize(horizontal: true, vertical: false)
                        scrollingTabs(sections, current)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { hairline }
                }
            }
        }
        // One container element, so tests find the bar while each tab keeps its own label (and the selected trait).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sectionBar")
    }

    private func select(_ s: Chapter) { model.nav.chapter = s }

    private static let tabFont = Font.custom("InstrumentSans-SemiBold", size: 14, relativeTo: .subheadline)
    private static let tabFontOn = Font.custom("InstrumentSans-Bold", size: 14, relativeTo: .subheadline)

    /// The tabs packed from the leading edge, as in s3.png (spread across a 600 pt column they read as unrelated labels).
    private func tabRow(_ sections: [Chapter], _ current: Chapter, padding: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(sections) { s in
                let on = s == current
                Button { select(s) } label: {
                    Text(s.title)
                        .font(on ? Self.tabFontOn : Self.tabFont)
                        .foregroundStyle(on ? PlayscribeColor.textPrimary : PlayscribeColor.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, padding)
                        .frame(minHeight: 48)
                        .overlay(alignment: .bottom) {
                            if on { Rectangle().fill(PlayscribeColor.accent).frame(height: 3).padding(.horizontal, padding) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .tappableFrame()
                .id("section-\(s.rawValue)")
            }
        }
    }

    /// Last step before the picker: the tabs scroll sideways, with 20 pt fades at the edges, and the current tab is scrolled
    /// into view whenever it changes.
    private func scrollingTabs(_ sections: [Chapter], _ current: Chapter) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                tabRow(sections, current, padding: 6).padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 20)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 20)
                }
            }
            .onAppear { proxy.scrollTo("section-\(current.rawValue)", anchor: .center) }
            .onChange(of: current) { withAnimation { proxy.scrollTo("section-\(current.rawValue)", anchor: .center) } }
        }
    }

    private func picker(_ sections: [Chapter], _ current: Chapter) -> some View {
        let index = (sections.firstIndex(of: current) ?? 0) + 1
        return Menu {
            ForEach(sections) { s in
                Button { select(s) } label: {
                    if s == current { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
                }
            }
        } label: {
            HStack(spacing: 12) {
                // One line, whole words, never wrapped (design sign, 13 Nov): the largest size that fits, from the reader's own
                // down to AX3, and never below AX3. The chevron is always kept.
                ViewThatFits(in: .horizontal) {
                    pickerTitle(current, cap: .accessibility5)
                    pickerTitle(current, cap: .accessibility4)
                    pickerTitle(current, cap: .accessibility3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PlayscribeColor.textPrimary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(current.title), section picker")
        .accessibilityValue("\(index) of \(sections.count)")
        .tappableFrame()
        .overlay(alignment: .bottom) { hairline }
    }

    private func pickerTitle(_ current: Chapter, cap: DynamicTypeSize) -> some View {
        Text(current.title)
            .font(PlayscribeFont.title2)
            .foregroundStyle(PlayscribeColor.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .dynamicTypeSize(...cap)
    }

    private func contents(_ sections: [Chapter], _ current: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sections) { s in
                let on = s == current
                Button { select(s) } label: {
                    Text(s.title)
                        .font(on ? PlayscribeFont.subheadline.weight(.semibold) : PlayscribeFont.subheadline)
                        .foregroundStyle(on ? PlayscribeColor.textPrimary : PlayscribeColor.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(on ? PlayscribeColor.ink700 : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .tappableFrame()
            }
        }
    }

    private var hairline: some View {
        Rectangle().fill(PlayscribeColor.ink600).frame(height: 1).accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// The bar pinned at the top of a scrolling game page (Card C: the only pinned element; art and title scroll away). Its
/// background is the page's, full width, and once it is pinned the list fades out over 26 pt beneath it, so no row is cut
/// mid-glyph. The bar itself keeps the column's reading width (600 pt at most on the open display).
struct PinnedSectionHeader: View {
    var gameID: String
    var ink: Color
    var inset: CGFloat = 20
    var maxWidth: CGFloat = .infinity
    @State private var pinned = false

    var body: some View {
        SectionBar(gameID: gameID)
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, inset)
            .frame(maxWidth: .infinity)
            .background(ink)
            .overlay(alignment: .bottom) {
                if pinned {
                    LinearGradient(colors: [ink, ink.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 26)
                        .offset(y: 26)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).minY <= 0.5 } action: { pinned = $0 }
            .zIndex(1)
    }
}
