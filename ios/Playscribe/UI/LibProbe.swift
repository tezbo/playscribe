import SwiftUI
import UIKit

/// TEMPORARY probe (v0.5.3, Library clear button investigation). Removed before merge.
enum LibProbe {
    static let t0 = Date()
    static let on = ProcessInfo.processInfo.arguments.contains("-libFocusProbe")
    /// Candidate under test: UIKit's own clear button instead of the custom one (-libNativeClear).
    static let nativeClear = ProcessInfo.processInfo.arguments.contains("-libNativeClear")
    static func log(_ s: @autoclosure () -> String) {
        guard on else { return }
        NSLog("LIBFOCUS %.3f %@", Date().timeIntervalSince(t0), s())
    }
}

extension LibProbe {
    /// First responder class, UIKit's view of the field, and the collapse inputs (query), at three moments.
    static func state(_ tag: String, query: @escaping () -> String) {
        func now(_ when: String) {
            let fr = KeyboardState.firstResponderInput
            log("\(tag) \(when): firstResponder=\(fr.map { String(describing: type(of: $0)) } ?? "none") fieldIsFR=\(KeyboardState.fieldIsFirstResponder) query='\(query())'")
        }
        now("t0")
        DispatchQueue.main.async { now("t+1runloop") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { now("t+50ms") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { now("t+500ms") }
    }
}

/// Sets UITextField.clearButtonMode on the Library search field (found by its placeholder), for the -libNativeClear candidate.
struct NativeClearButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { let v = UIView(); v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ v: UIView, context: Context) {
        DispatchQueue.main.async {
            func find(_ x: UIView) -> UITextField? {
                if let f = x as? UITextField, f.placeholder == "Search your library" { return f }
                for s in x.subviews { if let f = find(s) { return f } }
                return nil
            }
            for scene in UIApplication.shared.connectedScenes {
                for w in (scene as? UIWindowScene)?.windows ?? [] { if let f = find(w) { f.clearButtonMode = .whileEditing } }
            }
        }
    }
}
