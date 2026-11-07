import Foundation

/// Internal tools (Simulate an update, Testing, debug overlay toggles) are for the simulator and
/// developer builds only. TestFlight and App Store builds carry a receipt, so they never show them.
/// (The Release configuration also defines INTERNAL for the QA gate, so a compile flag is not enough.)
enum BuildChannel {
    /// Tests only: pretend this build is (true) or is not (false) a TestFlight / App Store build.
    nonisolated(unsafe) static var overrideIsDistribution: Bool?

    static var isDistribution: Bool {
        if let forced = overrideIsDistribution { return forced }
        #if targetEnvironment(simulator)
        // The simulator has a sandboxReceipt URL too, but it never runs a TestFlight or App Store
        // build, and QA scripts every route there. (A device keeps the receipt check below.)
        return false
        #else
        return isDistribution(receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
        #endif
    }

    /// A TestFlight or App Store build carries a receipt named "sandboxReceipt" or "receipt".
    static func isDistribution(receiptName: String?) -> Bool {
        guard let receiptName else { return false }
        return receiptName == "sandboxReceipt" || receiptName == "receipt"
    }
    static var showsInternalTools: Bool { !isDistribution }

    /// The Team alerts toggle only (Terry's call, 6 Nov): shown on development builds and TestFlight (receipt "sandboxReceipt"),
    /// hidden on the App Store ("receipt"). Every other internal tool stays behind the full `showsInternalTools` guard.
    static var showsTeamAlerts: Bool {
        if let forced = overrideIsDistribution { return !forced }
        #if targetEnvironment(simulator)
        return true
        #else
        return showsTeamAlerts(receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
        #endif
    }

    static func showsTeamAlerts(receiptName: String?) -> Bool { receiptName != "receipt" }
}
