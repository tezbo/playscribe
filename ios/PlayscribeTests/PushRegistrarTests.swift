import Testing
import Foundation
@testable import Playscribe

/// The relay client against a stubbed URLProtocol (0.5.1 push): an unchanged follows list sends nothing, a failed send is
/// retried on the next change, any non-2xx counts as failure, and a 401 registers again and retries once.
nonisolated final class StubRelay: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var seen: [URLRequest] = []

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
        Self.seen.append(r)
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
        PushRegistrar.resetForTests()
    }

    private func paths() -> [String] { StubRelay.seen.map { "\($0.httpMethod ?? "") \($0.url!.path)" } }

    @Test func unchangedListSendsNothingTheSecondTime() async {
        setUp()
        StubRelay.handler = { _ in (200, Data()) }
        await PushRegistrar.syncFollows(follows)?.value
        await PushRegistrar.syncFollows(follows)?.value
        let puts = StubRelay.seen.filter { $0.httpMethod == "PUT" && $0.url!.path == "/v1/devices/me/follows" }
        #expect(puts.count == 1, "one PUT for two identical lists, got \(paths())")
        #expect(puts.first?.value(forHTTPHeaderField: "Authorization") == "Bearer key-1")
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
        store.write("k-test")
        #expect(store.read() == "k-test")
        store.write(nil)
        #expect(store.read() == nil)
        // An earlier build's UserDefaults key moves over and is removed.
        UserDefaults.standard.set("old", forKey: "deviceKey")
        #expect(store.read() == "old")
        #expect(UserDefaults.standard.string(forKey: "deviceKey") == nil)
        store.write(nil)
    }
}
