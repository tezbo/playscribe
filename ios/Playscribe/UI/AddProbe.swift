import Foundation

/// TEMPORARY launch-settling probe (v0.5.3 investigation). Removed before merge.
enum AddProbe {
    static let t0 = Date()
    static let on = ProcessInfo.processInfo.arguments.contains("-addFocusProbe")
    static func log(_ s: @autoclosure () -> String) {
        guard on else { return }
        NSLog("ADDFOCUS %.2f %@", Date().timeIntervalSince(t0), s())
    }
}
