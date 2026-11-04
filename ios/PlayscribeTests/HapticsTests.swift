import Testing
import Foundation
@testable import Playscribe

struct HapticsTests {
    @Test func throttleAllowsOnePer400ms() {
        var t = HapticThrottle()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let first = t.allow(at: t0)
        let at200 = t.allow(at: t0.addingTimeInterval(0.2))
        let at390 = t.allow(at: t0.addingTimeInterval(0.39))
        let at410 = t.allow(at: t0.addingTimeInterval(0.41))
        #expect(first && !at200 && !at390 && at410)
    }
}
