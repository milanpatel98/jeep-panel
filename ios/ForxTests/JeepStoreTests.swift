import Foundation
import Synchronization
import Testing
@testable import Forx

// MARK: - Fakes

private nonisolated enum TestData {
    static let vin = "1C4JJXP60RW000000"
    static let start = Date(timeIntervalSince1970: 1_792_843_200)

    static func session(expiresIn seconds: TimeInterval) -> Session {
        Session(
            uid: "uid-fake",
            aws: AWSCredentials(
                accessKeyId: "AKIAFAKEACCESSKEY",
                secretAccessKey: "fake-secret-key",
                sessionToken: "fake-session-token"),
            expiresAt: start.addingTimeInterval(seconds))
    }
}

/// Uconnect API fake. Each call succeeds with fixture data unless a failure is queued for it.
/// `holdSends` parks `send` until `releaseSends()`.
private nonisolated final class FakeAPI: UconnectAPIProtocol {
    private nonisolated struct State {
        var failures: [String: [UconnectError]] = [:]
        var calls: [String: Int] = [:]
        var sent: [JeepCommand] = []
        var holdSends = false
        var waiting: [CheckedContinuation<Void, Never>] = []
        var updates = 0
        var status: Data? = nil
    }

    private let state = Mutex(State())

    var sent: [JeepCommand] { state.withLock { $0.sent } }
    var waitingSends: Int { state.withLock { $0.waiting.count } }
    var updates: Int { state.withLock { $0.updates } }
    func calls(_ method: String) -> Int { state.withLock { $0.calls[method] ?? 0 } }

    /// Queues failures for the next calls of `method` ("vehicles", "info", "status", "location", "send").
    func fail(_ method: String, _ errors: UconnectError...) {
        state.withLock { $0.failures[method, default: []].append(contentsOf: errors) }
    }

    /// Replaces the remote-status fixture for the following reads.
    func setStatus(_ json: String) {
        state.withLock { $0.status = Data(json.utf8) }
    }

    func holdSends(_ hold: Bool) {
        state.withLock { $0.holdSends = hold }
    }

    func releaseSends() {
        let waiting = state.withLock { s in
            let w = s.waiting
            s.waiting = []
            return w
        }
        for c in waiting { c.resume() }
    }

    private func record(_ method: String) throws(UconnectError) {
        let failure: UconnectError? = state.withLock { s in
            s.calls[method, default: 0] += 1
            guard var queue = s.failures[method], !queue.isEmpty else { return nil }
            let first = queue.removeFirst()
            s.failures[method] = queue
            return first
        }
        if let failure { throw failure }
    }

    func vehicles() async throws(UconnectError) -> [VehicleSummary] {
        try record("vehicles")
        return [VehicleSummary(vin: TestData.vin, nickname: nil, services: ["RDL", "RDU", "HBLF"])]
    }

    func info(vin: String) async throws(UconnectError) -> Data {
        try record("info")
        return Fixture.data("vehicle_info")
    }

    func remoteStatus(vin: String) async throws(UconnectError) -> Data {
        try record("status")
        return state.withLock { $0.status } ?? Fixture.data("remote_status")
    }

    func location(vin: String) async throws(UconnectError) -> Data {
        try record("location")
        return Data("{}".utf8)
    }

    func send(_ cmd: JeepCommand, vin: String, pin: String) async throws(UconnectError) {
        let hold = state.withLock { s in
            s.sent.append(cmd)
            return s.holdSends
        }
        if hold {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                state.withLock { $0.waiting.append(c) }
            }
        }
        try record("send")
    }

    func update(session: Session) async {
        state.withLock { $0.updates += 1 }
    }
}

private nonisolated final class FakeAuth: UconnectAuthProtocol {
    private let state: Mutex<(result: Result<Session, UconnectError>, calls: Int)>

    init(_ result: Result<Session, UconnectError>) {
        state = Mutex((result, 0))
    }

    var calls: Int { state.withLock { $0.calls } }

    func setResult(_ result: Result<Session, UconnectError>) {
        state.withLock { $0.result = result }
    }

    func login(email: String, password: String) async throws(UconnectError) -> Session {
        let result = state.withLock { s in
            s.calls += 1
            return s.result
        }
        switch result {
        case .success(let session): return session
        case .failure(let error): throw error
        }
    }
}

private nonisolated final class FakeVault: VaultProtocol {
    private nonisolated struct State {
        var creds: (email: String, password: String, pin: String)?
        var session: Session?
    }

    private let state: Mutex<State>

    init(signedIn: Bool, session: Session?) {
        let creds: (email: String, password: String, pin: String)? =
            signedIn ? (email: "driver@example.com", password: "fake-password", pin: "0000") : nil
        state = Mutex(State(creds: creds, session: session))
    }

    var hasCreds: Bool { state.withLock { $0.creds != nil } }

    func save(email: String, password: String, pin: String) throws {
        state.withLock { $0.creds = (email, password, pin) }
    }

    func load() -> (email: String, password: String, pin: String)? {
        state.withLock { $0.creds }
    }

    func saveSession(_ session: Session) {
        state.withLock { $0.session = session }
    }

    func loadSession() -> Session? {
        state.withLock { $0.session }
    }

    func forgetPin() {
        state.withLock { $0.creds = nil }  // load() needs all three
    }

    func clear() {
        state.withLock { $0 = State() }
    }
}

private nonisolated final class FakeFaceID: FaceIDGate {
    private let state: Mutex<(answer: FaceIDAnswer, asked: [String])>

    init(answer: Bool) {
        state = Mutex((answer ? .confirmed : .declined, []))
    }

    var asked: [String] { state.withLock { $0.asked } }

    func setAnswer(_ answer: Bool) {
        state.withLock { $0.answer = answer ? .confirmed : .declined }
    }

    func setUnavailable() {
        state.withLock { $0.answer = .unavailable }
    }

    func confirm(reason: String) async -> FaceIDAnswer {
        state.withLock { s in
            s.asked.append(reason)
            return s.answer
        }
    }
}

/// Sleep that waits until the test fires it, so the 60 s deadline and the 4 s message are deterministic.
private final class ManualSleep {
    private var waiters: [(duration: Duration, continuation: CheckedContinuation<Void, Never>)] = []

    func waiting(_ duration: Duration) -> Int {
        waiters.filter { $0.duration == duration }.count
    }

    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters.append((duration, c))
        }
    }

    func fire(_ duration: Duration) {
        let due = waiters.filter { $0.duration == duration }
        waiters.removeAll { $0.duration == duration }
        for w in due { w.continuation.resume() }
    }

    func fireAll() {
        let all = waiters
        waiters = []
        for w in all { w.continuation.resume() }
    }
}

/// The store's clock; tests move it forward.
private final class TestClock {
    var now = TestData.start

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// Lets queued main-actor work run until `condition` holds (bounded).
private func settle(until condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() {
        await Task.yield()
    }
}

private final class Harness {
    let api: FakeAPI
    let auth: FakeAuth
    let vault: FakeVault
    let faceID: FakeFaceID
    let sleeper: ManualSleep
    let clock: TestClock
    let cache: SnapshotCache
    let store: JeepStore

    init(
        signedIn: Bool = true,
        session: Session? = TestData.session(expiresIn: 3600),
        login: Result<Session, UconnectError> = .success(TestData.session(expiresIn: 3600)),
        faceIDAnswer: Bool = true
    ) {
        let api = FakeAPI()
        let auth = FakeAuth(login)
        let vault = FakeVault(signedIn: signedIn, session: session)
        let faceID = FakeFaceID(answer: faceIDAnswer)
        let sleeper = ManualSleep()
        let clock = TestClock()
        let cache = SnapshotCache(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("JeepStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("snapshot.json"))
        self.api = api
        self.auth = auth
        self.vault = vault
        self.faceID = faceID
        self.sleeper = sleeper
        self.clock = clock
        self.cache = cache
        store = JeepStore(
            makeAPI: { _ in api },
            auth: auth,
            vault: vault,
            faceID: faceID,
            cache: cache,
            now: { clock.now },
            sleep: { await sleeper.sleep($0) })
    }

    /// Releases every parked sleep so no task is left suspended.
    func finish() {
        api.releaseSends()
        sleeper.fireAll()
    }
}

private let noAnswer = "Jeep didn't answer. Try again."

private let unlockedStatus = #"""
{"doors": {"driver": {"status": "UNLOCKED"}, "passenger": {"status": "UNLOCKED"},
 "leftRear": {"status": "UNLOCKED"}, "rightRear": {"status": "UNLOCKED"}},
 "engine": {"status": "OFF"}}
"""#

// MARK: - Tests

struct JeepStoreTests {
    @Test func secondTapWhilePendingIsIgnored() async {
        let h = Harness()
        await h.store.refresh()
        h.api.holdSends(true)

        let first = Task { await h.store.perform(.lock) }
        await settle { h.api.waitingSends == 1 }
        #expect(h.store.pending == [.lock])

        await h.store.perform(.lock)
        #expect(h.api.sent == [.lock])

        h.api.releaseSends()
        await first.value
        #expect(h.api.sent == [.lock])
        #expect(h.store.pending.isEmpty)
        #expect(h.store.message == nil)
        h.finish()
    }

    @Test func failureReverts() async {
        let h = Harness()
        await h.store.refresh()
        let before = h.store.snapshot
        h.api.fail("send", .commandFailed, .timeout)

        await h.store.perform(.lock)
        #expect(h.api.sent == [.lock])
        #expect(h.store.pending.isEmpty)
        #expect(h.store.message == noAnswer)
        #expect(h.store.messageId == 1)
        #expect(h.store.snapshot == before)
        #expect(h.api.calls("info") == 1)  // no refresh after a failure
        #expect((h.store.patch["pending"] as? [String: Bool])?["lock"] == false)
        #expect(h.store.patch["message"] as? String == noAnswer)

        // The same copy again still counts as a new message.
        await h.store.perform(.lock)
        #expect(h.store.pending.isEmpty)
        #expect(h.store.message == noAnswer)
        #expect(h.store.messageId == 2)
        #expect(h.store.patch["messageId"] as? Int == 2)

        // Cleared after 4 s.
        await settle { h.sleeper.waiting(.seconds(4)) == 2 }
        h.sleeper.fire(.seconds(4))
        await settle { h.store.message == nil }
        #expect(h.store.message == nil)
        #expect(h.store.messageId == 2)
        h.finish()
    }

    @Test func uiDeadlineRevertsAfter60s() async {
        let h = Harness()
        await h.store.refresh()
        h.api.holdSends(true)

        let first = Task { await h.store.perform(.lock) }
        await settle { h.api.waitingSends == 1 && h.sleeper.waiting(.seconds(60)) == 1 }
        #expect(h.store.pending == [.lock])

        h.sleeper.fire(.seconds(60))
        await settle { h.store.pending.isEmpty }
        #expect(h.store.pending.isEmpty)
        #expect(h.store.message == noAnswer)

        // The call answers late: the UI stays reverted; only a refresh picks up the real state.
        h.api.releaseSends()
        await first.value
        #expect(h.store.pending.isEmpty)
        #expect(h.store.messageId == 1)
        #expect(h.api.calls("info") == 2)
        #expect(h.api.sent == [.lock])
        h.finish()
    }

    @Test func unlockNeedsFaceIDOnPhone() async {
        let h = Harness(faceIDAnswer: false)
        await h.store.refresh()

        await h.store.perform(.unlock)
        #expect(h.faceID.asked == ["Unlock your Jeep"])
        #expect(h.api.sent.isEmpty)
        #expect(h.store.pending.isEmpty)
        #expect(h.store.message == nil)

        h.faceID.setAnswer(true)
        await h.store.perform(.unlock)
        #expect(h.faceID.asked.count == 2)
        #expect(h.api.sent == [.unlock])
        h.finish()
    }

    @Test func unlockFromCarPlaySkipsFaceID() async {
        let h = Harness(faceIDAnswer: false)
        await h.store.refresh()

        await h.store.perform(.unlock, fromCarPlay: true)
        #expect(h.faceID.asked.isEmpty)
        #expect(h.api.sent == [.unlock])
        h.finish()
    }

    @Test func lockSkipsFaceID() async {
        let h = Harness(faceIDAnswer: false)
        await h.store.refresh()

        await h.store.perform(.lock)
        #expect(h.faceID.asked.isEmpty)
        #expect(h.api.sent == [.lock])
        h.finish()
    }

    @Test func gateNeedsFaceIDOnPhone() async {
        let h = Harness(faceIDAnswer: false)
        await h.store.refresh()

        await h.store.perform(.gate)
        #expect(h.faceID.asked == ["Open the tailgate"])
        #expect(h.api.sent.isEmpty)
        #expect(h.store.pending.isEmpty)

        await h.store.perform(.gate, fromCarPlay: true)
        #expect(h.faceID.asked.count == 1)
        #expect(h.api.sent == [.gate])

        h.faceID.setAnswer(true)
        await h.store.perform(.gate)
        #expect(h.faceID.asked.count == 2)
        #expect(h.api.sent == [.gate, .gate])
        h.finish()
    }

    @Test func noFaceIDOrPasscodeSaysSo() async {
        let h = Harness()
        h.faceID.setUnavailable()
        await h.store.refresh()

        await h.store.perform(.unlock)
        #expect(h.api.sent.isEmpty)
        #expect(h.store.pending.isEmpty)
        #expect(h.store.message == "Set up Face ID or a passcode to unlock.")
        h.finish()
    }

    @Test func badPinStopsAndAsks() async throws {
        let h = Harness()
        await h.store.refresh()
        h.api.fail("send", .badPin)

        await h.store.perform(.lock)
        #expect(h.api.sent == [.lock])
        #expect(h.store.pending.isEmpty)
        #expect(h.store.message == "PIN is wrong. Sign in again.")
        #expect(h.store.signInNote == "PIN is wrong. Sign in again.")
        #expect(h.store.needsSignIn == true)
        #expect(h.vault.load() == nil)  // the wrong PIN is forgotten, also across launches

        // No commands, and no refresh, until signed in again.
        await h.store.perform(.lock)
        await h.store.perform(.horn)
        await h.store.refresh()
        #expect(h.api.sent == [.lock])
        #expect(h.api.calls("info") == 1)

        try await h.store.signIn(email: "driver@example.com", password: "fake-password", pin: "1234")
        #expect(h.store.needsSignIn == false)
        #expect(h.store.signInNote == nil)
        await h.store.perform(.lock)
        #expect(h.api.sent == [.lock, .lock])
        h.finish()
    }

    @Test func confirmedLockShowsLockedRightAway() async {
        let h = Harness()
        h.api.setStatus(unlockedStatus)
        await h.store.refresh()
        #expect(h.store.snapshot?.locked == false)

        // Remote status still says unlocked after the Jeep confirmed Lock: show the confirmed state.
        await h.store.perform(.lock)
        #expect(h.store.snapshot?.locked == true)
        #expect(h.store.patch["locked"] as? Bool == true)
        #expect(h.cache.load()?.locked == true)
        #expect(h.store.pending.isEmpty)
        #expect(h.store.message == nil)

        // The next refresh corrects it.
        await h.store.refresh()
        #expect(h.store.snapshot?.locked == false)
        h.finish()
    }

    @Test func confirmedUnlockShowsUnlockedRightAway() async {
        let h = Harness()
        await h.store.refresh()
        #expect(h.store.snapshot?.locked == true)

        await h.store.perform(.unlock)
        #expect(h.store.snapshot?.locked == false)
        #expect(h.store.patch["locked"] as? Bool == false)
        h.finish()
    }

    @Test func failedLockLeavesStateAlone() async {
        let h = Harness()
        h.api.setStatus(unlockedStatus)
        await h.store.refresh()
        h.api.fail("send", .commandFailed)

        await h.store.perform(.lock)
        #expect(h.store.snapshot?.locked == false)
        h.finish()
    }

    @Test func climateOnFor15MinOrUntilOff() async {
        let h = Harness()
        await h.store.refresh()
        func climateOn() -> Bool? { (h.store.patch["climate"] as? [String: Any])?["on"] as? Bool }
        #expect(climateOn() == false)

        // A failed start shows nothing.
        h.api.fail("send", .commandFailed)
        await h.store.perform(.climateOn)
        #expect(climateOn() == false)

        await h.store.perform(.climateOn)
        #expect(climateOn() == true)
        h.clock.advance(15 * 60 - 1)
        #expect(climateOn() == true)
        h.clock.advance(1)
        #expect(climateOn() == false)  // the Jeep's remote start has ended

        await h.store.perform(.climateOn)
        #expect(climateOn() == true)
        await h.store.perform(.climateOff)
        #expect(climateOn() == false)

        // A failed Off keeps it on.
        await h.store.perform(.climateOn)
        h.api.fail("send", .timeout)
        await h.store.perform(.climateOff)
        #expect(climateOn() == true)
        h.finish()
    }

    @Test func reloginFailureStopsAndAsks() async {
        let h = Harness(login: .failure(.badLogin))
        #expect(h.store.needsSignIn == false)
        h.api.fail("vehicles", .sessionExpired, .sessionExpired, .sessionExpired)

        await h.store.refresh()
        await h.store.refresh()
        await h.store.perform(.lock)

        #expect(h.auth.calls == 1)
        #expect(h.store.needsSignIn == true)
        #expect(h.api.updates == 0)
        #expect(h.api.sent.isEmpty)
        h.finish()
    }

    @Test func reloginUnexpectedFailureBacksOff() async {
        // A session about to expire: every refresh wants a login.
        let h = Harness(session: TestData.session(expiresIn: 60), login: .failure(.unexpected("HTTP 500")))

        await h.store.refresh()
        #expect(h.auth.calls == 1)
        #expect(h.store.needsSignIn == false)  // not a sign-in problem: back off instead

        // Foreground ticks, pull-to-refresh and taps don't log in again for 15 min.
        await h.store.refresh()
        await h.store.perform(.lock)
        h.clock.advance(5 * 60)
        await h.store.refresh()
        h.clock.advance(10 * 60 - 1)
        await h.store.refresh()
        #expect(h.auth.calls == 1)
        #expect(h.api.sent.isEmpty)

        h.clock.advance(1)  // 15 min after the first
        await h.store.refresh()
        #expect(h.auth.calls == 2)

        // Second failure in a row: 30 min.
        h.clock.advance(30 * 60 - 1)
        await h.store.refresh()
        #expect(h.auth.calls == 2)
        h.clock.advance(1)
        await h.store.refresh()
        #expect(h.auth.calls == 3)

        // Third: 60 min. Fourth and later: capped at 2 h.
        h.clock.advance(60 * 60)
        await h.store.refresh()
        #expect(h.auth.calls == 4)
        h.clock.advance(2 * 60 * 60)
        await h.store.refresh()
        #expect(h.auth.calls == 5)
        h.clock.advance(2 * 60 * 60 - 1)
        await h.store.refresh()
        #expect(h.auth.calls == 5)
        h.clock.advance(1)
        await h.store.refresh()
        #expect(h.auth.calls == 6)

        // It works again: logged in, and the Jeep is read.
        h.auth.setResult(.success(Session(
            uid: "uid-fake", aws: TestData.session(expiresIn: 0).aws,
            expiresAt: h.clock.now.addingTimeInterval(4 * 3600))))
        h.clock.advance(2 * 60 * 60)
        await h.store.refresh()
        #expect(h.auth.calls == 7)
        #expect(h.store.snapshot != nil)
        #expect(h.store.needsSignIn == false)
        h.finish()
    }

    @Test func loginsAreAtLeastFiveMinutesApart() async {
        let h = Harness(session: TestData.session(expiresIn: 60))
        await h.store.refresh()
        #expect(h.auth.calls == 1)

        // The API says the new session expired right away (e.g. a phone clock that is off).
        h.api.fail("info", .sessionExpired)
        await h.store.refresh()
        #expect(h.auth.calls == 1)

        h.clock.advance(5 * 60)
        h.api.fail("info", .sessionExpired)
        await h.store.refresh()
        #expect(h.auth.calls == 2)
        h.finish()
    }

    @Test func reloginRejectedStopsAndAsks() async {
        // Any Gigya error from accounts.login (locked account, rate limit): stop and ask.
        let h = Harness(session: TestData.session(expiresIn: 60), login: .failure(.loginRejected(403120)))

        await h.store.refresh()
        #expect(h.store.needsSignIn == true)
        h.clock.advance(3 * 60 * 60)
        await h.store.refresh()
        await h.store.perform(.lock)
        #expect(h.auth.calls == 1)
        #expect(h.api.sent.isEmpty)
        h.finish()
    }

    @Test func nearExpirySessionLogsInOnceFirst() async {
        let h = Harness(session: TestData.session(expiresIn: 60))

        await h.store.refresh()
        #expect(h.auth.calls == 1)
        #expect(h.api.updates == 1)
        #expect(h.vault.loadSession()?.expiresAt == TestData.session(expiresIn: 3600).expiresAt)
        #expect(h.store.snapshot != nil)
        #expect(h.store.vin == TestData.vin)
        h.finish()
    }

    @Test func expiredSessionReloginsAndRetriesOnce() async {
        let h = Harness()
        h.api.fail("info", .sessionExpired)

        await h.store.refresh()
        #expect(h.auth.calls == 1)
        #expect(h.api.updates == 1)
        #expect(h.api.calls("info") == 2)
        #expect(h.store.snapshot != nil)
        #expect(h.store.needsSignIn == false)
        h.finish()
    }

    @Test func sessionExpiredMidCommandIsNotResent() async {
        let h = Harness()
        await h.store.refresh()
        h.api.fail("send", .sessionExpired)

        await h.store.perform(.lock)
        #expect(h.api.sent == [.lock])
        #expect(h.store.pending.isEmpty)
        #expect(h.store.message == noAnswer)
        #expect(h.auth.calls == 1)
        #expect(h.api.updates == 1)
        h.finish()
    }

    @Test func offlineUsesCache() async throws {
        let h = Harness()
        let cached = JeepSnapshot(
            nickname: nil, locked: true, doorsOpen: [], tailgateOpen: false,
            rangeMiles: 186, fuelPercent: 60, evPercent: 78, pluggedIn: true, charging: false,
            chargeMinutesLeft: nil, tiresPsi: ["FL": 35], odometerMiles: 7671,
            latitude: 0.0, longitude: 0.0, supported: [.lock, .unlock],
            updatedAt: TestData.start.addingTimeInterval(-600))
        try h.cache.save(cached)
        h.api.fail("vehicles", .network)

        await h.store.refresh()
        #expect(h.store.snapshot == cached)
        #expect(h.store.offline == true)
        #expect(h.store.patch["offline"] as? Bool == true)
        #expect(h.store.needsSignIn == false)
        #expect(h.auth.calls == 0)
        h.finish()
    }

    @Test func signInSavesAndRefreshes() async throws {
        let h = Harness(signedIn: false, session: nil)
        #expect(h.store.needsSignIn == true)

        try await h.store.signIn(email: "driver@example.com", password: "fake-password", pin: "0000")
        #expect(h.store.needsSignIn == false)
        #expect(h.vault.hasCreds)
        #expect(h.vault.loadSession() != nil)
        #expect(h.auth.calls == 1)
        #expect(h.store.snapshot != nil)
        #expect(h.store.vin == TestData.vin)

        h.store.signOut()
        #expect(h.store.needsSignIn == true)
        #expect(h.store.snapshot == nil)
        #expect(h.store.vin == nil)
        #expect(h.vault.hasCreds == false)
        h.finish()
    }

    @Test func signedInEmail() async throws {
        let h = Harness(signedIn: false, session: nil)
        #expect(h.store.email == nil)
        try await h.store.signIn(email: "driver@example.com", password: "fake-password", pin: "0000")
        #expect(h.store.email == "driver@example.com")
        h.store.signOut()
        #expect(h.store.email == nil)
        h.finish()
    }

    @Test func onSnapshotSeesEveryNewReading() async throws {
        let h = Harness()
        var seen: [(previous: JeepSnapshot?, current: JeepSnapshot)] = []
        h.store.onSnapshot = { seen.append(($0, $1)) }
        await h.store.refresh()
        #expect(seen.count == 1)
        #expect(seen.first?.previous == nil)
        #expect(seen.first?.current == h.store.snapshot)
        let first = h.store.snapshot
        h.api.fail("info", .network)
        await h.store.refresh()
        #expect(seen.count == 1)  // a failed refresh is not a new reading
        await h.store.refresh()
        #expect(seen.count == 2)
        #expect(seen.last?.previous == first)
        h.finish()
    }

    @Test func lastKnownSnapshotFallsBackToCache() async throws {
        let h = Harness()
        #expect(h.store.lastKnownSnapshot == nil)
        let cached = JeepSnapshot(
            nickname: nil, locked: true, doorsOpen: [], tailgateOpen: false,
            rangeMiles: 186, fuelPercent: 60, evPercent: 78, pluggedIn: true, charging: true,
            chargeMinutesLeft: 30, tiresPsi: ["FL": 35], odometerMiles: 7671,
            latitude: 0.0, longitude: 0.0, supported: [.lock],
            updatedAt: TestData.start.addingTimeInterval(-900))
        try h.cache.save(cached)
        #expect(h.store.snapshot == nil)
        #expect(h.store.lastKnownSnapshot == cached)  // before the store has shown anything
        await h.store.refresh()
        #expect(h.store.lastKnownSnapshot == h.store.snapshot)
        #expect(h.store.lastKnownSnapshot != cached)
        h.finish()
    }
}
