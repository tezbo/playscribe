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
