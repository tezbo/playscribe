import XCTest

/// ci-ui-tests-hidden-failures, acceptance 1: a deliberately failing UI test must turn the iOS UI check red. Temporary: removed
/// in the next commit once the red run is recorded.
final class CIRedProbeTests: XCTestCase {
    func testDeliberateFailure() {
        XCTFail("deliberate failure: the iOS UI check must be red on this commit")
    }
}
