import Testing
import Foundation
@testable import Playscribe

struct HapticsTests {
    @Test func throttleAllowsOnePer400ms() {
        var t = HapticThrottle()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(t.allow(at: t0))
        #expect(!t.allow(at: t0.addingTimeInterval(0.2)))
        #expect(!t.allow(at: t0.addingTimeInterval(0.39)))
        #expect(t.allow(at: t0.addingTimeInterval(0.41)))
    }
}
