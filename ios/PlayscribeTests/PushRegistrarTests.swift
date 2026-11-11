import Testing
import Foundation
@testable import Playscribe

/// The relay client against a stubbed URLProtocol (0.5.1 push): an unchanged follows list sends nothing, a failed send is
/// retried on the next change, any non-2xx counts as failure, and a 401 registers again and retries once.
nonisolated final class StubRelay: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    private static let lock = NSLock()
    /// Requests the stub has served; read through `snapshot()` so a loading thread's append cannot race the assertion.
    nonisolated(unsafe) private static var _seen: [URLRequest] = []
    static var seen: [URLRequest] {
        get { lock.lock(); defer { lock.unlock() }; return _seen }
        set { lock.lock(); defer { lock.unlock() }; _seen = newValue }
    }
    static func record(_ r: URLRequest) { lock.lock(); _seen.append(r); lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var r = request
        // The body of a streamed request arrives as a stream; keep it readable for the assertions.
        if r.httpBody == nil, let s = r.httpBodyStream {
            s.open(); defer { s.close() }
            var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
            r.httpBody = d
        }
        Self.record(r)
        let (code, data) = Self.handler?(r) ?? (200, Data())
        let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor @Suite(.serialized) struct PushRegistrarTests {
    private let follows = [PushRegistrar.Follow(gameId: "dawnwalker", igdbId: nil, notify: "major")]

    private func setUp(key: String? = "key-1") {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubRelay.self]
        PushRegistrar.session = URLSession(configuration: config)
        PushRegistrar.relayOverride = URL(string: "https://relay.test")
        PushRegistrar.keys = .memory(key)
        StubRelay.seen = []
        StubRelay.handler = nil
        PushRegistrar.appCallsEnabled = false
        PushRegistrar.resetForTests()
    }

    private func paths() -> [String] { StubRelay.seen.map { "\($0.httpMethod ?? "") \($0.url!.path)" } }
    private func json(_ r: URLRequest) -> [String: Any] { (try? JSONSerialization.jsonObject(with: r.httpBody ?? Data())) as? [String: Any] ?? [:] }

    // MARK: "Help keep my games up to date" (0.5.4, N-9): ids and the relay's key, nothing else.

    /// The promise, pinned: the body is `{ follows: [...] }` and each item is exactly one of gameId or igdbId. A new field here
    /// fails this test (and the relay refuses it), so what leaves the phone cannot grow unnoticed.
    @Test func keepCurrentBodyHoldsTheFollowIdsAndNothingElse() throws {
        let follows = [
            PushRegistrar.Follow(gameId: "dawnwalker", igdbId: 329130, notify: "major"),
            PushRegistrar.Follow(gameId: nil, igdbId: 119171, notify: "off"),   // a game added by hand: IGDB number only
            PushRegistrar.Follow(gameId: nil, igdbId: nil, notify: "all"),       // nothing to send for this one
        ]
        let data = try #require(PushRegistrar.keepCurrentBody(follows))
        let top = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Array(top.keys) == ["follows"], "the body holds the follows and nothing else: \(top.keys)")
        let items = try #require(top["follows"] as? [[String: Any]])
        #expect(items.count == 2)
        for item in items {
            #expect(item.count == 1, "an item is one id: \(item)")
            #expect(Set(item.keys).isSubset(of: ["gameId", "igdbId"]), "only an id, never a level: \(item)")
        }
        #expect(items[0]["gameId"] as? String == "dawnwalker")
        #expect(items[1]["igdbId"] as? Int == 119171)
        #expect(String(decoding: data, as: UTF8.self) == #"{"follows":[{"gameId":"dawnwalker"},{"igdbId":119171}]}"#)
    }

    @Test func turnOnRegistersIdsOnlyWithoutAKeyThenUpdatesAndDeletesWithIt() async throws {
        setUp(key: nil)
        StubRelay.handler = { r in
            if r.httpMethod == "POST", r.url!.path == "/v1/follows" { return (201, Data(#"{"deviceKey":"k-follows","follows":[]}"#.utf8)) }
            return (r.httpMethod == "DELETE" ? 204 : 200, Data())
        }
        // Nothing before the first follow: an empty list never makes a record (Quinn).
        #expect(PushRegistrar.syncKeepCurrent(true, follows: []) == nil)
        #expect(StubRelay.seen.isEmpty)
        await PushRegistrar.syncKeepCurrent(true, follows: follows)?.value
        let post = try #require(StubRelay.seen.first)
        #expect(paths() == ["POST /v1/follows"])
        #expect(post.value(forHTTPHeaderField: "Authorization") == nil, "no key exists yet, so none is sent")
        #expect(Array(json(post).keys) == ["follows"])
        #expect(PushRegistrar.keys.read() == "k-follows")
        #expect(PushRegistrar.keepCurrentLastSent != nil)
        // The next save with the same list sends nothing; a changed list is a PUT of ids only, with the key.
        await PushRegistrar.syncKeepCurrent(true, follows: follows)?.value
        #expect(paths().count == 1, "an unchanged list within the week sends nothing: \(paths())")
        let more = follows + [PushRegistrar.Follow(gameId: nil, igdbId: 7, notify: "all")]
        await PushRegistrar.syncKeepCurrent(true, follows: more)?.value
        let put = try #require(StubRelay.seen.last)
        #expect(paths().last == "PUT /v1/devices/me/follows")
        #expect(put.value(forHTTPHeaderField: "Authorization") == "Bearer k-follows")
        #expect(String(decoding: put.httpBody ?? Data(), as: UTF8.self) == #"{"follows":[{"gameId":"dawnwalker"},{"igdbId":7}]}"#)
        // Off: the record is deleted and the key forgotten.
        await PushRegistrar.syncKeepCurrent(false, follows: more)?.value
        #expect(paths().last == "DELETE /v1/devices/me")
        #expect(PushRegistrar.keys.read() == nil)
        #expect(PushRegistrar.keepCurrentLastSent == nil)
    }

    @Test func onAPushDeviceTheSwitchOnlySetsTheHourlyFlag() async throws {
        setUp()   // key-1 from a push registration (no "follows" record kind)
        StubRelay.handler = { _ in (200, Data()) }
        await PushRegistrar.syncKeepCurrent(true, follows: follows)?.value
        #expect(paths() == ["PATCH /v1/devices/me"])
        #expect(json(StubRelay.seen[0]) as? [String: Bool] == ["hourly": true])
        await PushRegistrar.syncKeepCurrent(true, follows: follows)?.value
        #expect(paths().count == 1, "the flag is sent once")
        await PushRegistrar.syncKeepCurrent(false, follows: follows)?.value
        #expect(json(StubRelay.seen.last!) as? [String: Bool] == ["hourly": false])
        #expect(PushRegistrar.keys.read() == "key-1", "a push device keeps its record")
    }

    @Test func aLostFollowsRecordIsMadeAgainOnA401() async throws {
        setUp(key: nil)
        var lost = false
        StubRelay.handler = { r in
            if r.httpMethod == "POST", r.url!.path == "/v1/follows" { return (201, Data(#"{"deviceKey":"k-\#(lost ? 2 : 1)","follows":[]}"#.utf8)) }
            if r.httpMethod == "PUT" { return (lost && r.value(forHTTPHeaderField: "Authorization") == "Bearer k-1" ? 401 : 200, Data()) }
            return (200, Data())
        }
        await PushRegistrar.syncKeepCurrent(true, follows: follows)?.value
        lost = true   // the relay forgot the record (expired)
        let more = follows + [PushRegistrar.Follow(gameId: "witcher-3", igdbId: nil, notify: "all")]
        await PushRegistrar.syncKeepCurrent(true, follows: more)?.value
        #expect(paths() == ["POST /v1/follows", "PUT /v1/devices/me/follows", "POST /v1/follows", "PUT /v1/devices/me/follows"], "\(paths())")
        #expect(PushRegistrar.keys.read() == "k-2")
        #expect(StubRelay.seen.last?.value(forHTTPHeaderField: "Authorization") == "Bearer k-2")
    }

    @Test func lastSentLineCountsDays() {
        let now = Date(timeIntervalSince1970: 1_762_900_000)
        #expect(KeepCurrentCopy.lastSent(nil, now: now) == nil)
        #expect(KeepCurrentCopy.lastSent(now.addingTimeInterval(-3600), now: now) == "Last sent: today")
        #expect(KeepCurrentCopy.lastSent(now.addingTimeInterval(-86_400), now: now) == "Last sent: yesterday")
        #expect(KeepCurrentCopy.lastSent(now.addingTimeInterval(-3 * 86_400), now: now) == "Last sent: 3 days ago")
    }

    @Test func unchangedListSendsNothingTheSecondTime() async {
        setUp()
        StubRelay.handler = { _ in (200, Data()) }
        func puts() -> [URLRequest] { StubRelay.seen.filter { $0.httpMethod == "PUT" && $0.url!.path == "/v1/devices/me/follows" } }
        await PushRegistrar.syncFollows(follows)?.value
        let first = puts()
        #expect(first.count == 1, "the first list is sent once: \(paths())")
        #expect(first.first?.value(forHTTPHeaderField: "Authorization") == "Bearer key-1")
        await PushRegistrar.syncFollows(follows)?.value
        #expect(puts().count == first.count, "the same list a second time sends nothing: \(paths())")
    }

    @Test func aFailedSendIsRetriedOnTheNextChange() async {
        setUp()
        StubRelay.handler = { _ in (500, Data()) }
        await PushRegistrar.syncFollows(follows)?.value
        StubRelay.handler = { _ in (200, Data()) }
        await PushRegistrar.syncFollows(follows)?.value
        let puts = StubRelay.seen.filter { $0.httpMethod == "PUT" }
        #expect(puts.count == 2, "a 500 is a failure, so the same list goes again: \(paths())")
    }

    @Test func a401RegistersAgainAndRetriesOnce() async {
        setUp(key: "stale")
        // Register once so the client has a token to register again with.
        StubRelay.handler = { r in
            r.url!.path == "/v1/devices" ? (200, Data(#"{"deviceKey":"fresh"}"#.utf8)) : (200, Data())
        }
        await PushRegistrar.register(token: "abc", follows: follows)?.value
        StubRelay.seen = []
        PushRegistrar.keys.write("stale")
        StubRelay.handler = { r in
            switch (r.httpMethod ?? "", r.url!.path) {
            case ("POST", "/v1/devices"): return (200, Data(#"{"deviceKey":"fresh"}"#.utf8))
            default: return r.value(forHTTPHeaderField: "Authorization") == "Bearer fresh" ? (200, Data()) : (401, Data())
            }
        }
        let other = [PushRegistrar.Follow(gameId: "kcd2", igdbId: nil, notify: "all")]
        await PushRegistrar.syncFollows(other)?.value
        let p = paths()
        #expect(p.contains("POST /v1/devices"), "a 401 registers again: \(p)")
        #expect(PushRegistrar.keys.read() == "fresh", "the new key replaces the stale one")
        let last = StubRelay.seen.last { $0.url!.path == "/v1/devices/me/follows" }
        #expect(last?.value(forHTTPHeaderField: "Authorization") == "Bearer fresh", "the retry carries the new key")
        #expect(p.filter { $0 == "PUT /v1/devices/me/follows" }.count == 2, "one try, one retry: \(p)")
    }

    @Test func aSecond401DoesNotLoop() async {
        setUp()
        StubRelay.handler = { r in r.url!.path == "/v1/devices" ? (200, Data(#"{"deviceKey":"fresh"}"#.utf8)) : (401, Data()) }
        await PushRegistrar.register(token: "abc", follows: follows)?.value
        StubRelay.seen = []
        PushRegistrar.keys.write("key-1")
        let other = [PushRegistrar.Follow(gameId: "wukong", igdbId: nil, notify: "all")]
        await PushRegistrar.syncFollows(other)?.value
        #expect(StubRelay.seen.count < 8, "bounded: \(paths())")
    }

    @Test func aQuietHoursRecoveryRegistersWithTheCurrentFollows() async {
        setUp()
        StubRelay.handler = { r in r.url!.path == "/v1/devices" ? (200, Data(#"{"deviceKey":"fresh"}"#.utf8)) : (200, Data()) }
        await PushRegistrar.register(token: "abc", follows: follows)?.value
        let current = [PushRegistrar.Follow(gameId: "blue-prince", igdbId: nil, notify: "all")]
        await PushRegistrar.syncFollows(current)?.value
        StubRelay.seen = []
        StubRelay.handler = { r in
            if r.url!.path == "/v1/devices" { return (200, Data(#"{"deviceKey":"fresh2"}"#.utf8)) }
            return r.value(forHTTPHeaderField: "Authorization") == "Bearer fresh2" ? (200, Data()) : (401, Data())
        }
        await PushRegistrar.syncQuietHours(QuietHours(from: 22 * 60, until: 8 * 60))?.value
        let post = StubRelay.seen.first { $0.url!.path == "/v1/devices" }
        let body = post?.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        #expect(body.contains("blue-prince") && !body.contains("dawnwalker"), "re-registered with the current list: \(body)")
    }

    #if DEBUG
    private func teamBodies() -> [String] {
        StubRelay.seen.compactMap { r in r.httpBody.map { String(decoding: $0, as: UTF8.self) } }.filter { $0.contains("\"team\"") }
    }

    /// A tester who turned Team alerts on in TestFlight and then installed the App Store build: the relay record still says
    /// team=true, so the App Store build says team=false once and forgets the stored choice.
    @Test func anAppStoreBuildAfterTestFlightClearsTeamOnceAndForgetsTheChoice() async {
        setUp()
        PushRegistrar.showsTeamForTests = false
        UserDefaults.standard.set(true, forKey: PushRegistrar.teamKey)
        defer { UserDefaults.standard.removeObject(forKey: PushRegistrar.teamKey); PushRegistrar.showsTeamForTests = nil }
        StubRelay.handler = { r in r.url!.path == "/v1/devices" ? (200, Data(#"{"deviceKey":"fresh"}"#.utf8)) : (200, Data()) }
        await PushRegistrar.register(token: "abc", follows: follows)?.value
        #expect(teamBodies() == [#"{"team":false}"#], "team=false once: \(teamBodies())")
        #expect(UserDefaults.standard.object(forKey: PushRegistrar.teamKey) == nil, "the stored choice is forgotten")
        StubRelay.seen = []
        await PushRegistrar.register(token: "abc", follows: follows)?.value
        #expect(teamBodies().isEmpty, "the next launch sends nothing about team")
    }

    @Test func aFailedClearKeepsTheChoiceSoItIsTriedAgain() async {
        setUp()
        PushRegistrar.showsTeamForTests = false
        UserDefaults.standard.set(true, forKey: PushRegistrar.teamKey)
        defer { UserDefaults.standard.removeObject(forKey: PushRegistrar.teamKey); PushRegistrar.showsTeamForTests = nil }
        // The relay fails every PATCH, including the team one (the handler never reads a body).
        StubRelay.handler = { r in
            r.url!.path == "/v1/devices" ? (200, Data(#"{"deviceKey":"fresh"}"#.utf8)) : (503, Data())
        }
        await PushRegistrar.register(token: "abc", follows: follows)?.value
        #expect(UserDefaults.standard.bool(forKey: PushRegistrar.teamKey), "kept for the next launch")
    }

    @Test func anAppStoreBuildThatNeverChoseSendsNothingAboutTeam() async {
        setUp()
        PushRegistrar.showsTeamForTests = false
        UserDefaults.standard.removeObject(forKey: PushRegistrar.teamKey)
        defer { PushRegistrar.showsTeamForTests = nil }
        StubRelay.handler = { r in r.url!.path == "/v1/devices" ? (200, Data(#"{"deviceKey":"fresh"}"#.utf8)) : (200, Data()) }
        await PushRegistrar.register(token: "abc", follows: follows)?.value
        #expect(teamBodies().isEmpty)
    }

    #endif

    @Test func nothingIsSentBeforeTheDeviceIsRegistered() async {
        setUp(key: nil)
        let task = PushRegistrar.syncFollows([PushRegistrar.Follow(gameId: "x", igdbId: nil, notify: "all")])
        #expect(task == nil)
        #expect(StubRelay.seen.isEmpty)
    }

    @Test func quietHoursRegistersAgainOn401TooAndFailsOnNon2xx() async {
        setUp(key: "stale")
        StubRelay.handler = { r in r.url!.path == "/v1/devices" ? (200, Data(#"{"deviceKey":"fresh"}"#.utf8)) : (200, Data()) }
        await PushRegistrar.register(token: "abc", follows: follows)?.value
        StubRelay.seen = []
        PushRegistrar.keys.write("stale")
        StubRelay.handler = { r in
            if r.url!.path == "/v1/devices" { return (200, Data(#"{"deviceKey":"fresh"}"#.utf8)) }
            return r.value(forHTTPHeaderField: "Authorization") == "Bearer fresh" ? (200, Data()) : (401, Data())
        }
        await PushRegistrar.syncQuietHours(QuietHours(from: 22 * 60, until: 8 * 60))?.value
        #expect(paths().contains("POST /v1/devices"), "the quiet-hours PATCH recovers from a 401 too: \(paths())")
        #expect(StubRelay.seen.last?.httpMethod == "PATCH")
        #expect(PushRegistrar.keys.read() == "fresh")
    }

    @Test func theKeychainKeepsAndForgetsTheKey() {
        let store = DeviceKeyStore.keychain
        store.write(nil)
        UserDefaults.standard.removeObject(forKey: "deviceKey")
        #expect(store.read() == nil)
        if store.write("k-test") {
            #expect(store.read() == "k-test")
            store.write(nil)
            #expect(store.read() == nil)
            // An earlier build's UserDefaults key moves over and is removed.
            UserDefaults.standard.set("old", forKey: "deviceKey")
            #expect(store.read() == "old")
            #expect(UserDefaults.standard.string(forKey: "deviceKey") == nil)
            store.write(nil)
        } else {
            // An unsigned build has no Keychain entitlement. The key must not be lost: it stays in UserDefaults.
            UserDefaults.standard.set("old", forKey: "deviceKey")
            #expect(store.read() == "old")
            #expect(UserDefaults.standard.string(forKey: "deviceKey") == "old", "the old copy stays while the Keychain refuses")
            UserDefaults.standard.removeObject(forKey: "deviceKey")
        }
    }

    @Test func forgetDeviceSendsDeleteAndDropsTheKeyOn204() async {
        setUp()
        StubRelay.handler = { _ in (204, Data()) }
        await PushRegistrar.forgetDevice()?.value
        let deletes = StubRelay.seen.filter { $0.httpMethod == "DELETE" }
        #expect(deletes.count == 1 && deletes.first?.url?.path == "/v1/devices/me", "one DELETE /v1/devices/me: \(paths())")
        #expect(deletes.first?.value(forHTTPHeaderField: "Authorization") == "Bearer key-1")
        #expect(PushRegistrar.keys.read() == nil, "a 204 means done, so the stored key is dropped")
        #expect(PushRegistrar.forgetDevice() == nil, "with no key there is nothing to send")
    }

    @Test func forgetDeviceKeepsTheKeyAndRetriesAfterAnOfflineFailure() async {
        setUp()
        StubRelay.handler = { _ in (503, Data()) }
        await PushRegistrar.forgetDevice()?.value
        #expect(PushRegistrar.keys.read() == "key-1", "a failed delete keeps the key so it can try again")
        StubRelay.handler = { _ in (204, Data()) }
        await PushRegistrar.forgetDevice()?.value
        #expect(StubRelay.seen.filter { $0.httpMethod == "DELETE" }.count == 2, "the next call sends it again")
        #expect(PushRegistrar.keys.read() == nil)
    }

    @Test func forgetDeviceTreats401AsDone() async {
        setUp(key: "stale")
        StubRelay.handler = { _ in (401, Data()) }
        await PushRegistrar.forgetDevice()?.value
        #expect(PushRegistrar.keys.read() == nil, "the relay no longer knows the key, so it is dropped")
    }
}
