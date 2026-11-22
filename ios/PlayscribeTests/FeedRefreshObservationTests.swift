import Foundation
import Observation
import Testing
@testable import Playscribe

/// bug-library-redraw-on-feed-refresh: a refresh that brings nothing new must not tell views that read `data`, the merged
/// releases or the index that they changed. Every such write re-ran the whole Library shelf (Quinn at #513 04e6e6c: about 24 of 33
/// runs in 20 swipes came from refreshes).
@MainActor
struct FeedRefreshObservationTests {
    private func model() -> AppModel {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "feed-obs-\(UUID().uuidString).json"))
        m.resetDemo()
        m.loadCachedFeed()
        m.notifyNewlyOnPS5()
        m.notifyNewlyOnPS5()   // settles knownOnPS5 and knownReported once, as a first refresh would
        return m
    }

    /// Whether `read` sees a change while `act` runs.
    private func changes(_ m: AppModel, reading read: @escaping (AppModel) -> Void, during act: () -> Void) -> Bool {
        let flag = Flag()
        withObservationTracking { read(m) } onChange: { flag.fired = true }
        act()
        return flag.fired
    }

    @Test func anUnchangedRefreshLeavesDataAlone() {
        let m = model()
        let releases = m.feedReleases
        let fired = changes(m, reading: { _ = $0.data }) {
            m.applyLatest(releases: releases, updatedAt: .now)
            m.notifyNewlyOnPS5()
        }
        #expect(!fired, "an unchanged refresh wrote AppModel.data")
    }

    @Test func anUnchangedRefreshLeavesTheMergedReleasesAlone() {
        let m = model()
        let releases = m.feedReleases
        let fired = changes(m, reading: { _ = $0.allReleasesMerged; _ = $0.feedReleases }) {
            m.applyLatest(releases: releases, updatedAt: .now)
        }
        #expect(!fired, "an unchanged refresh wrote the merged releases")
    }

    @Test func aNewlyOnPS5ReleaseStillReachesData() throws {
        let m = model()
        var known = m.data.knownOnPS5 ?? []
        let onPS5 = m.data.collection.flatMap { m.releases($0.gameID) }.filter { $0.ps5State == .onPS5 && !$0.isAlertWorthy() }
        let first = try #require(onPS5.first?.id, "the bundled library has a past On PS5 release")
        known.remove(first)
        m.data.knownOnPS5 = known
        let fired = changes(m, reading: { _ = $0.data }) { m.notifyNewlyOnPS5() }
        #expect(fired, "a release newly On PS5 must still be recorded")
        #expect(m.data.knownOnPS5?.contains(first) == true)
    }
}

/// onChange is a Sendable closure, so it sets a flag on a reference rather than a captured var. Outside the @MainActor test
/// type and marked nonisolated (this target defaults to MainActor), so the Sendable closure can set it. It is set synchronously on the writing (main) thread, inside `act`.
nonisolated private final class Flag: @unchecked Sendable { var fired = false }
