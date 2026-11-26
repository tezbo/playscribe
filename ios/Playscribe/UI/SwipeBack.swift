import SwiftUI
import UIKit

/// Keeps the edge-swipe back gesture on a screen that hides the system back button (r053-tap-opens-tick-adds, Iris).
/// UIKit turns the gesture off when the back button is hidden; this gives it a delegate that lets it begin whenever there
/// is a screen to go back to, and puts the previous delegate back when the screen goes away.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ controller: Host, context: Context) {}

    final class Host: UIViewController, UIGestureRecognizerDelegate {
        private weak var previousDelegate: UIGestureRecognizerDelegate?
        private weak var configured: UINavigationController?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let nav = navigationController, let gesture = nav.interactivePopGestureRecognizer else { return }
            if configured !== nav {
                previousDelegate = gesture.delegate
                configured = nav
            }
            gesture.delegate = self
            gesture.isEnabled = true
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let gesture = configured?.interactivePopGestureRecognizer, gesture.delegate === self {
                gesture.delegate = previousDelegate
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

extension View {
    /// Use together with `.navigationBarBackButtonHidden(true)`.
    func keepsSwipeBack() -> some View { background(SwipeBackEnabler().frame(width: 0, height: 0).accessibilityHidden(true)) }
}

/// A sideways swipe that never holds a vertical scroll (N-1, N-9: "Not now or a swipe"). It is a UIKit pan that only begins when
/// the finger moves mainly sideways, so the page's own pan takes every vertical drag that starts on the card. A SwiftUI
/// DragGesture on scroll content, exclusive or simultaneous, held the page still once the card sat under the finger: at AX3
/// and AX5 in Closed landscape the alerts card's buttons could not be scrolled into view (cloud runs a0f1e86 and fbdf2a7, #635).
struct SideSwipe: UIGestureRecognizerRepresentable {
    var action: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        if Self.dismisses(recognizer.translation(in: nil)) { action() }
    }

    /// Far enough, and mainly sideways.
    static func dismisses(_ t: CGPoint) -> Bool { abs(t.x) > 60 && abs(t.x) > 2 * abs(t.y) }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: nil)
            return abs(v.x) > 2 * abs(v.y)
        }
    }
}
