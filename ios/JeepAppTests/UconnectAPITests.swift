import Foundation
import Synchronization
import Testing
@testable import JeepApp

/// Manual clock: `sleep` advances it instead of waiting, so polling tests are instant and deterministic.
private nonisolated final class FakeClock: Sendable {
    private let current: Mutex<Date>

    init(_ start: Date = Date(timeIntervalSince1970: 1_792_843_200)) {
        current = Mutex(start)
    }

    var now: Date { current.withLock { $0 } }

    func advance(_ duration: Duration) {
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        current.withLock { $0 += seconds }
    }
}

private let vin = "1C4JJXP60RW000000"
private let testPin = "1234"  // fake test PIN

private nonisolated func pathHas(_ fragment: String) -> @Sendable (URLRequest) -> Bool {
    { ($0.url?.path() ?? "").contains(fragment) }
}

private nonisolated func isCommandPost(_ request: URLRequest) -> Bool {
    request.httpMethod == "POST" && (request.url?.path() ?? "").hasSuffix("/remote/")
}

private func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func makeAPI(_ stub: StubTransport, clock: FakeClock = FakeClock()) -> UconnectAPI {
    let session = Session(
        uid: "uid-fake",
        aws: AWSCredentials(
            accessKeyId: "AKIAFAKEACCESSKEY",
            secretAccessKey: "fake-secret-key",
            sessionToken: "fake-session-token"),
        expiresAt: .distantFuture)
    return UconnectAPI(
        transport: stub,
        session: session,
        now: { clock.now },
        sleep: { clock.advance($0) })
}

struct UconnectAPITests {
    @Test func commandPollsUntilSuccess() async throws {
        let stub = StubTransport()
        stub.enqueue(body: Fixture.data("pin_ok"), match: pathHas("/pin/authenticate/"))
        stub.enqueue(body: Fixture.data("command_ok"), match: { isCommandPost($0) })
        stub.enqueue(body: Fixture.data("status_pending"), match: pathHas("/last-status/"))
        stub.enqueue(body: Fixture.data("status_success"), match: pathHas("/last-status/"))

        try await makeAPI(stub).send(.lock, vin: vin, pin: testPin)

        let sent = stub.sent
        #expect(sent.count == 4)
        guard sent.count == 4 else { return }

        // PIN: MFA gateway, default sdp, base64 of the PIN
        #expect(sent[0].httpMethod == "POST")
        #expect(sent[0].url?.absoluteString
            == "https://mfa.fcl-02.fcagcv.com/v1/accounts/uid-fake/ignite/pin/authenticate/")
        #expect(sent[0].value(forHTTPHeaderField: "x-api-key") == UconnectBrand.mfa.key)
        let pinBody = try bodyJSON(sent[0])
        #expect(pinBody["pin"] as? String == Data(testPin.utf8).base64EncodedString())
        #expect(pinBody["pin"] as? String == "MTIzNA==")

        // Command: v1 remote/ with the PIN token
        #expect(sent[1].url?.absoluteString
            == "https://channels.sdpr-02.fcagcv.com/v1/accounts/uid-fake/vehicles/\(vin)/remote/")
        #expect(sent[1].value(forHTTPHeaderField: "x-api-key") == UconnectBrand.api.key)
        let commandBody = try bodyJSON(sent[1])
        #expect(commandBody["command"] as? String == "RDL")
        #expect(commandBody["pinAuth"] as? String == "pin-token")

        // Status polls
        for request in sent[2...] {
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString
                == "https://channels.sdpr-02.fcagcv.com/v1/accounts/uid-fake/vehicles/\(vin)/remote/corr-1/last-status/")
        }

        // Every API call is SigV4-signed
        for request in sent {
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("AWS4-HMAC-SHA256 ") == true)
            #expect(request.value(forHTTPHeaderField: "X-Amz-Security-Token") == "fake-session-token")
        }
    }

    @Test func pollTimesOutAt60s() async {
        let clock = FakeClock()
        let start = clock.now
        let stub = StubTransport()
        stub.enqueue(body: Fixture.data("pin_ok"), match: pathHas("/pin/authenticate/"))
        stub.enqueue(body: Fixture.data("command_ok"), match: { isCommandPost($0) })
        for _ in 0..<40 {
            stub.enqueue(body: Fixture.data("status_pending"), match: pathHas("/last-status/"))
        }

        await #expect(throws: UconnectError.timeout) {
            try await makeAPI(stub, clock: clock).send(.lock, vin: vin, pin: testPin)
        }

        let polls = stub.sent.filter { ($0.url?.path() ?? "").hasSuffix("/last-status/") }.count
        #expect(polls >= 1)
        #expect(polls <= 21)
        let waited = clock.now.timeIntervalSince(start)
        #expect(waited >= 60)
        #expect(waited <= 63)
    }

    @Test func failureStatusThrows() async {
        let stub = StubTransport()
        stub.enqueue(body: Fixture.data("pin_ok"), match: pathHas("/pin/authenticate/"))
        stub.enqueue(body: Fixture.data("command_ok"), match: { isCommandPost($0) })
        stub.enqueue(body: Fixture.data("status_failure"), match: pathHas("/last-status/"))

        await #expect(throws: UconnectError.commandFailed) {
            try await makeAPI(stub).send(.unlock, vin: vin, pin: testPin)
        }
    }

    @Test func badPinIsBadPin() async {
        let stub = StubTransport()
        stub.enqueue(status: 401, body: Data(#"{"message": "Invalid PIN"}"#.utf8), match: pathHas("/pin/authenticate/"))

        await #expect(throws: UconnectError.badPin) {
            try await makeAPI(stub).send(.lock, vin: vin, pin: testPin)
        }
        #expect(stub.sent.count == 1)  // no command sent
    }

    @Test func pinTokenIsCached() async throws {
        let stub = StubTransport()
        stub.enqueue(body: Fixture.data("pin_ok"), match: pathHas("/pin/authenticate/"))
        for _ in 0..<2 {
            stub.enqueue(body: Fixture.data("command_ok"), match: { isCommandPost($0) })
            stub.enqueue(body: Fixture.data("status_success"), match: pathHas("/last-status/"))
        }

        let api = makeAPI(stub)
        try await api.send(.lock, vin: vin, pin: testPin)
        try await api.send(.horn, vin: vin, pin: testPin)

        let pinCalls = stub.sent.filter { ($0.url?.path() ?? "").hasSuffix("/pin/authenticate/") }.count
        #expect(pinCalls == 1)
    }

    @Test func vehiclesListAndSdpRouteTheGate() async throws {
        let stub = StubTransport()
        stub.enqueue(body: Fixture.data("vehicles"), match: { ($0.url?.path() ?? "").hasSuffix("/vehicles/") })
        stub.enqueue(body: Fixture.data("pin_ok"), match: pathHas("/pin/authenticate/"))
        stub.enqueue(body: Fixture.data("command_ok"), match: { isCommandPost($0) })
        stub.enqueue(body: Fixture.data("status_success"), match: pathHas("/last-status/"))

        let api = makeAPI(stub)
        let vehicles = try await api.vehicles()
        #expect(vehicles.count == 1)
        #expect(vehicles.first?.vin == vin)
        #expect(vehicles.first?.nickname == "Test Jeep")
        #expect(vehicles.first?.services == ["RDL", "RDU", "HBLF", "REON", "REOFF"])

        try await api.send(.gate, vin: vin, pin: testPin)

        let sent = stub.sent
        #expect(sent.count == 4)
        guard sent.count == 4 else { return }
        #expect(sent[0].url?.absoluteString
            == "https://channels.sdpr-02.fcagcv.com/v4/accounts/uid-fake/vehicles/?stage=ALL&sdp=ALL&brand=ALL")
        // sdp from the vehicle list, not the default
        #expect(sent[1].url?.path() == "/v1/accounts/uid-fake/ignite/pin/authenticate/")
        // the liftgate is a v2 command
        #expect(sent[2].url?.path() == "/v2/accounts/uid-fake/vehicles/\(vin)/remote/")
        #expect(try bodyJSON(sent[2])["command"] as? String == "ROLIFTGATEUNLOCK")
    }

    @Test func readEndpoints() async throws {
        let stub = StubTransport()
        stub.enqueue(status: 404, body: Data(#"{"message": "Not Found"}"#.utf8), match: pathHas("/v3/"))
        stub.enqueue(body: Fixture.data("vehicle_info"), match: pathHas("/v4/"))
        stub.enqueue(body: Fixture.data("remote_status"), match: pathHas("/remote/status/"))
        stub.enqueue(body: Data(#"{"latitude": 0.0, "longitude": 0.0}"#.utf8), match: pathHas("/location/lastknown/"))
        stub.enqueue(body: Fixture.data("vehicle_info"), match: pathHas("/v4/"))

        let api = makeAPI(stub)
        #expect(try await api.info(vin: vin) == Fixture.data("vehicle_info"))
        #expect(try await api.remoteStatus(vin: vin) == Fixture.data("remote_status"))
        _ = try await api.location(vin: vin)
        _ = try await api.info(vin: vin)  // remembers v4, no second v3 try

        let paths = stub.sent.map { $0.url?.path() ?? "" }
        #expect(paths == [
            "/v3/accounts/uid-fake/vehicles/\(vin)/status/",
            "/v4/accounts/uid-fake/vehicles/\(vin)/status/",
            "/v1/accounts/uid-fake/vehicles/\(vin)/remote/status/",
            "/v1/accounts/uid-fake/vehicles/\(vin)/location/lastknown/",
            "/v4/accounts/uid-fake/vehicles/\(vin)/status/",
        ])
    }

    @Test func expiredTokenIsSessionExpired() async {
        let stub = StubTransport()
        stub.enqueue(
            status: 403,
            body: Data(#"{"message": "The security token included in the request is expired"}"#.utf8),
            match: pathHas("/remote/status/"))

        await #expect(throws: UconnectError.sessionExpired) {
            _ = try await makeAPI(stub).remoteStatus(vin: vin)
        }
    }

    @Test func otherHTTPErrorIsUnexpected() async {
        let stub = StubTransport()
        stub.enqueue(status: 403, body: Data(#"{"message": "Forbidden"}"#.utf8), match: pathHas("/remote/status/"))

        await #expect(throws: UconnectError.unexpected("remote status: HTTP 403")) {
            _ = try await makeAPI(stub).remoteStatus(vin: vin)
        }
    }
}
