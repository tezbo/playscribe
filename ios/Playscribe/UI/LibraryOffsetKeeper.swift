import SwiftUI
import UIKit

/// bug-library-back-scroll-jump, #513 regression (Mac f3ca6f4, Closed, fill-library/12: the tile came back 85 pt lower on Back, main c56a776 did not).
/// The page's scroll id is held outside the model and restored by id, which lands on the top of the id's container, not where the
/// page was. This remembers the scroll view's own offset when the Library goes away and puts it back after the pop, when it differs.
@MainActor
final class LibraryOffsetKeeper {
    private weak var scrollView: UIScrollView?
    private var saved: CGFloat?

    func attach(_ view: UIScrollView?) { scrollView = view }

    func freeze() { saved = scrollView?.contentOffset.y }

    /// After the pop has laid out. A page that is already where it was, within a point, is left alone.
    func restore() {
        guard let sv = scrollView, let y = saved else { return }
        saved = nil
        if abs(sv.contentOffset.y - y) > 1 { sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: y), animated: false) }
    }
}

/// Finds the scroll view this sits in (it is placed in the scroll view's content) and hands it to the keeper.
struct LibraryScrollFinder: UIViewRepresentable {
    var keeper: LibraryOffsetKeeper

    func makeUIView(context: Context) -> UIView {
        let v = UIView(); v.isUserInteractionEnabled = false; v.isAccessibilityElement = false; return v
    }

    func updateUIView(_ view: UIView, context: Context) {
        let keeper = keeper
        DispatchQueue.main.async {
            var up: UIView? = view.superview
            while let u = up, !(u is UIScrollView) { up = u.superview }
            keeper.attach(up as? UIScrollView)
        }
    }
}
