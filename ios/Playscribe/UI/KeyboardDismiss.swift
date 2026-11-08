import SwiftUI
import UIKit

/// A tap anywhere but a text field, a control or a list row puts the keyboard away (Terry, 8 Nov).
///
/// This is a UIKit recognizer on the window, not a SwiftUI tap gesture: a tap on the typed text is taken by the UITextField
/// itself and never reaches SwiftUI, so a SwiftUI handler could not tell "tap inside the field" from "tap outside" and
/// dropped focus on both (cc04658 Mac hand check 1). The recognizer does not cancel or delay any touch.
private final class KeyboardDismissView: UIView, UIGestureRecognizerDelegate {
    private weak var attachedTo: UIWindow?
    private lazy var tap: UITapGestureRecognizer = {
        let r = UITapGestureRecognizer(target: self, action: #selector(tapped))
        r.cancelsTouchesInView = false
        r.delaysTouchesBegan = false
        r.delaysTouchesEnded = false
        r.delegate = self
        return r
    }()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachedTo?.removeGestureRecognizer(tap)
        attachedTo = window
        window?.addGestureRecognizer(tap)
    }

    @objc private func tapped() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var v = touch.view
        while let x = v {
            // Fields keep the caret and the keyboard; controls and list rows do their own job (a pick in Add keeps the keyboard up).
            if x is UITextField || x is UITextView || x is UIControl || x is UICollectionViewCell || x is UITableViewCell { return false }
            v = x.superview
        }
        return true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

private struct KeyboardDismissAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { let v = KeyboardDismissView(); v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension View {
    /// Scrolling dismisses the keyboard, and so does a tap outside fields, controls and list rows.
    func dismissesKeyboardOnOutsideTap() -> some View {
        scrollDismissesKeyboard(.interactively).background(KeyboardDismissAnchor())
    }
}

enum KeyboardState {
    /// True when a text field or text view really is first responder in some window (not just SwiftUI's FocusState).
    static var fieldIsFirstResponder: Bool {
        func find(_ v: UIView) -> Bool { ((v is UITextField || v is UITextView) && v.isFirstResponder) || v.subviews.contains(where: find) }
        return UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows }.flatMap { $0 }.contains(where: find)
    }
}
