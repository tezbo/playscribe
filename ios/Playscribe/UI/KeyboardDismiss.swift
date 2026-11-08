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
        if ProcessInfo.processInfo.arguments.contains("-addFocusProbe"), let w = window {
            w.addGestureRecognizer(probeTap)
            if textObserver == nil {
                textObserver = NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: nil, queue: .main) { _ in
                    NSLog("ADDCARET textDidChange: %@", Self.fieldInfo())
                }
            }
        }
    }

    /// TEMPORARY diagnosis (v0.5.3, caret test): `-addFocusProbe` logs one ADDCARET line per tap and per text change.
    private lazy var probeTap: UITapGestureRecognizer = {
        let r = UITapGestureRecognizer(target: self, action: #selector(probeTapped(_:)))
        r.cancelsTouchesInView = false; r.delaysTouchesBegan = false; r.delaysTouchesEnded = false
        r.delegate = ProbeDelegate.shared
        return r
    }()
    private var textObserver: NSObjectProtocol?

    private static func fieldInfo() -> String {
        func find(_ v: UIView) -> UITextField? { (v as? UITextField).flatMap { $0.isFirstResponder ? $0 : nil } ?? v.subviews.lazy.compactMap(find).first }
        for w in UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.windows }).flatMap({ $0 }) {
            if let f = find(w) {
                let start = f.selectedTextRange.map { f.offset(from: f.beginningOfDocument, to: $0.start) } ?? -1
                let end = f.selectedTextRange.map { f.offset(from: f.beginningOfDocument, to: $0.end) } ?? -1
                let frame = f.convert(f.bounds, to: nil)
                return "text='\(f.text ?? "")' sel=\(start)-\(end) fieldFrame=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
            }
        }
        return "no-first-responder-field"
    }

    @objc private func probeTapped(_ r: UITapGestureRecognizer) {
        let p = r.location(in: nil)
        NSLog("ADDCARET tap at=%d,%d before: %@", Int(p.x), Int(p.y), Self.fieldInfo())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSLog("ADDCARET tap+400ms: %@", Self.fieldInfo()) }
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

private final class ProbeDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = ProbeDelegate()
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
