import XCTest

/// Walk-test trust (Nadia, 0.5.7 walk at f1fdde8): LibraryBackScrollTests AX5 came back 149 pt and 125 pt off with the simulator
/// stuck in landscape, so its numbers were Closed landscape's. A check that needs an orientation asks for it, waits for the window
/// to have that shape, and fails plainly when it never does instead of measuring the wrong layout (RailSetTests did the same, #543).
extension XCUIApplication {
    /// Sets the device orientation and waits up to 15 s for the app's window to match it. False, with a failure recorded, if it never does.
    @MainActor @discardableResult
    func require(_ orientation: UIDeviceOrientation, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCUIDevice.shared.orientation = orientation
        let wantWide = orientation.isLandscape
        func matches() -> Bool {
            let f = windows.firstMatch.frame
            return f.width > 0 && (f.width > f.height) == wantWide
        }
        let deadline = Date().addingTimeInterval(15)
        while !matches() && Date() < deadline { sleep(1) }
        guard matches() else {
            XCTFail("the window did not turn \(wantWide ? "landscape" : "portrait") within 15 s (\(windows.firstMatch.frame)); this run measures nothing",
                    file: file, line: line)
            return false
        }
        return true
    }
}
