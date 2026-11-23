import SwiftUI

/// R-7, "scroll edges fade" (bug-063, bug-library-tabbar-edge-fade): one soft edge for every scrolling page, in the page's own
/// ink, so a row is never sliced at full brightness where the page meets a bar. One gradient, two placements:
/// - `.below`: hangs under a view that stays put while the list scrolls beneath it (the pinned section bar). The list fades out
///   as it passes under the bar.
/// - `.bottom`: sits inside a scroll view's bottom edge (above the floating tab bar, the pill or the screen edge). The list fades
///   out over the last stretch, and solid ink runs on below the frame to the screen edge, because the scroll view draws rows on
///   into the bottom safe area (Quinn, Closed AX5 at 722c752, Open landscape at 7cb8b33). Views laid out after the page (rail,
///   tab bar, pill) still draw over it.
/// An overlay in the ink, not a mask: a masked scroll view is no longer the one the navigation bar tracks (354d15c, 9914a80), and a
/// mask clips whatever extends past the frame. Never hit-testable and hidden from VoiceOver, so a row under it stays tappable.
struct EdgeFade: ViewModifier {
    enum Placement { case below, bottom }
    var placement: Placement
    var ink: Color
    var active: Bool
    /// 24 pt at standard text, growing with Dynamic Type so an AX5 line (about 60 pt) still fades over most of its height.
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = EdgeFade.height
    /// The fade's height at standard text (Iris names the final value; R-7).
    static let height: CGFloat = 24
    /// Never more than this, so at AX5 the fade covers less than one line's worth of the visible page.
    static let maxHeight: CGFloat = 56

    var fadeHeight: CGFloat { min(scaled, Self.maxHeight) }

    func body(content: Content) -> some View {
        switch placement {
        case .below:
            content.overlay(alignment: .bottom) {
                if active {
                    gradient(from: ink, to: ink.opacity(0))
                        .frame(height: fadeHeight)
                        .offset(y: fadeHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        case .bottom:
            content
                .overlay(alignment: .bottom) {
                    if active {
                        gradient(from: ink.opacity(0), to: ink)
                            .frame(height: fadeHeight)
                            .overlay(alignment: .bottom) { ink.frame(height: 120).offset(y: 120) }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
    }

    private func gradient(from: Color, to: Color) -> some View {
        LinearGradient(colors: [from, to], startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    /// The list fades out under this view (a pinned bar) while `active`.
    func fadesListBelow(ink: Color = PlayscribeRole.bg, active: Bool = true) -> some View {
        modifier(EdgeFade(placement: .below, ink: ink, active: active))
    }

    /// The scroll view's content fades out at its bottom edge. End the content with `EdgeFadeClearance()` so its last row comes
    /// to rest clear of the fade. Apply it to the scroll view before `clearsMessages()`, so the fade sits on the page's edge, not
    /// in the pad below it.
    func fadesAtBottomEdge(ink: Color = PlayscribeRole.bg, active: Bool = true) -> some View {
        modifier(EdgeFade(placement: .bottom, ink: ink, active: active))
    }
}

/// The last thing in a page that uses `fadesAtBottomEdge()`: one fade of empty space, so the last row comes to rest clear of the
/// fade (and of the bar below it). A view in the content, not `contentMargins`, which every nested scroll view (a chip row, the
/// You might also like covers) would inherit.
struct EdgeFadeClearance: View {
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = EdgeFade.height
    var body: some View {
        Color.clear.frame(height: min(scaled, EdgeFade.maxHeight)).accessibilityHidden(true).allowsHitTesting(false)
    }
}
