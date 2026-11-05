import Foundation

/// Internal tools (Simulate an update, Testing, debug overlay toggles) are for the simulator and
/// developer builds only. TestFlight and App Store builds carry a receipt, so they never show them.
/// (The Release configuration also defines INTERNAL for the QA gate, so a compile flag is not enough.)
enum BuildChannel {
    /// Tests only: pretend this build is (true) or is not (false) a TestFlight / App Store build.
    nonisolated(unsafe) static var overrideIsDistribution: Bool?

    static var isDistribution: Bool {
        if let forced = overrideIsDistribution { return forced }
        guard let name = Bundle.main.appStoreReceiptURL?.lastPathComponent else { return false }
        return name == "sandboxReceipt" || name == "receipt"
    }
    static var showsInternalTools: Bool { !isDistribution }
}
