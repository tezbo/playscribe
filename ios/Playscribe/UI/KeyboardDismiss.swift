import SwiftUI
import UIKit

/// A tap anywhere but a text field, a control or a list row puts the keyboard away (Terry, 8 Nov).
///
/// This is a UIKit recognizer on the window, not a SwiftUI tap gesture: a tap on the typed text is taken by the UITextField
/// itself and never reaches SwiftUI, so a SwiftUI handler could not tell "tap inside the field" from "tap outside" and
/// dropped focus on both (cc04658 Mac hand check 1). The recognizer does not cancel or delay any touch.
final class KeepsKeyboardMarkerView: UIView {}

private struct KeepsKeyboardMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { let v = KeepsKeyboardMarkerView(); v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

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

    /// The text input that was first responder when the touch began. A tap that itself gives a field focus (the padding of the search
    /// row, right after the keyboard was put away) must not be undone by this recognizer: it resigns only the responder that was
    /// already there when the touch began, one run-loop turn after the tap ends (9d41ce0 Mac hand check: a padding tap just after a
    /// title tap showed nothing once).
    private weak var responderAtTouch: UIView?

    @objc private func tapped() {
        FocusProbe.log("dismiss recognizer tapped (responder at touch start: \(responderAtTouch == nil ? "none" : "a field"))")
        let before = responderAtTouch
        DispatchQueue.main.async {
            guard let before, before.isFirstResponder else { return }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        responderAtTouch = KeyboardState.firstResponderInput
        var v = touch.view
        while let x = v {
            // Fields keep the caret and the keyboard.
            if x is UITextField || x is UITextView { return false }
            // Controls do their own job, except the navigation bar's title: in Open portrait it is a UIControl and a tap on the
            // sheet title must still put the keyboard away (6a0a4b4 Mac hand check a). Matched by class name, verified only on the Mac's
            // iPhone Duo simulator (iOS 27.1 target, 934ff71 gate); a non-name test is a 0.5.4 card.
            if x is UIControl, !String(describing: type(of: x)).contains("Title") { return false }
            // Only rows that mark themselves keep the keyboard (a pick in Add); section headers are cells too in a SwiftUI List
            // and a tap on one must dismiss (6a0a4b4 hand check b).
            if x is UICollectionViewCell || x is UITableViewCell, Self.containsMarker(x) { return false }
            v = x.superview
        }
        return true
    }

    private static func containsMarker(_ v: UIView) -> Bool { v is KeepsKeyboardMarkerView || v.subviews.contains(where: containsMarker) }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

private struct KeyboardDismissAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { let v = KeyboardDismissView(); v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension View {
    /// Marks a list row whose tap must leave the keyboard up (a pick in Add).
    func keepsKeyboardOnTap() -> some View { background(KeepsKeyboardMarker()) }

    /// Scrolling dismisses the keyboard, and so does a tap outside fields, controls and list rows.
    func dismissesKeyboardOnOutsideTap() -> some View {
        scrollDismissesKeyboard(.interactively).background(KeyboardDismissAnchor())
    }
}

enum KeyboardState {
    /// The text field or text view that is first responder now, if any.
    static var firstResponderInput: UIView? {
        func find(_ v: UIView) -> UIView? {
            if (v is UITextField || v is UITextView) && v.isFirstResponder { return v }
            for s in v.subviews { if let f = find(s) { return f } }
            return nil
        }
        for scene in UIApplication.shared.connectedScenes {
            for w in (scene as? UIWindowScene)?.windows ?? [] { if let f = find(w) { return f } }
        }
        return nil
    }

    /// True when a text field or text view really is first responder in some window (not just SwiftUI's FocusState).
    static var fieldIsFirstResponder: Bool {
        func find(_ v: UIView) -> Bool { ((v is UITextField || v is UITextView) && v.isFirstResponder) || v.subviews.contains(where: find) }
        return UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows }.flatMap { $0 }.contains(where: find)
    }
}
