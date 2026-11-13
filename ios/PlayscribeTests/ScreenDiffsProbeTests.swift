// THROWAWAY (reverted next commit): a PR test that calls app code main does not have.
import Testing
@testable import Playscribe

struct ScreenDiffsProbeTests {
    @Test func probe() { #expect(ScreenDiffsProbe.value == 507) }
}
