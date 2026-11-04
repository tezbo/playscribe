
@MainActor
struct PillTimerTests {
    @Test func pillDismissesItself() async throws {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "pill-\(UUID().uuidString).json"))
        m.showPill(gameID: "g", releaseID: "r1", after: 0.1)
        #expect(m.pill?.releaseID == "r1")
        try await Task.sleep(for: .milliseconds(400))
        #expect(m.pill == nil)
    }

    @Test func newerPillSurvivesOlderTimer() async throws {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "pill-\(UUID().uuidString).json"))
        m.showPill(gameID: "g", releaseID: "r1", after: 0.1)
        m.showPill(gameID: "g", releaseID: "r2", after: 5)
        try await Task.sleep(for: .milliseconds(400))
        #expect(m.pill?.releaseID == "r2")
    }
}
