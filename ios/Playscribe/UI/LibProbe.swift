import Foundation

/// TEMPORARY probe (v0.5.3, Library clear button investigation). Removed before merge.
enum LibProbe {
    static let t0 = Date()
    static let on = ProcessInfo.processInfo.arguments.contains("-libFocusProbe")
    static func log(_ s: @autoclosure () -> String) {
        guard on else { return }
        NSLog("LIBFOCUS %.3f %@", Date().timeIntervalSince(t0), s())
    }
}
