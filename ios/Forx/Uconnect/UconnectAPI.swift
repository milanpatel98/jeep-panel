import Foundation

/// A vehicle from the account's vehicle list.
nonisolated struct VehicleSummary: Sendable, Equatable {
    var vin: String
    var nickname: String?
    /// Services that are both `vehicleCapable` and `serviceEnabled`.
    var services: [String]
}

/// Signed client for the Uconnect vehicle API, ported from py-uconnect's `api.py`
/// (plus the command polling of `client.py`). Read methods return the raw JSON.
/// Nothing here is logged: the PIN, tokens, VIN and location are secrets.
actor UconnectAPI: UconnectAPIProtocol {
    /// `DEFAULT_SDP`: service delivery platform used for PIN auth when the vehicle list has none.
    nonisolated static let defaultSDP = "ignite"
    /// A cached PIN token is renewed this long before it expires.
    nonisolated static let pinTokenMargin: TimeInterval = 30
    /// Requests stop this long before the AWS credentials expire (`REFRESH_MARGIN`).
    nonisolated static let sessionMargin: TimeInterval = 5 * 60
    nonisolated static let pollInterval: Duration = .seconds(3)
    nonisolated static let commandTimeout: TimeInterval = 60
    /// Versions of the vehicle status endpoint (`STATUS_API_VERSIONS`).
    nonisolated static let statusVersions = ["v3", "v4"]

    private nonisolated static let succeeded: Set<String> = ["success", "succeeded", "completed", "complete"]
    private nonisolated static let failed: Set<String> = ["failure", "failed", "error", "rejected", "timeout"]
    private nonisolated static let rejected: Set<String> = ["failure", "failed", "error", "rejected"]

    private nonisolated struct PinToken {
        let token: String
        let validUntil: Date
    }

    private let transport: any HTTPTransport
    private var session: Session
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    private var sdpByVIN: [String: String] = [:]
    private var statusVersionByVIN: [String: String] = [:]
    private var pinTokens: [String: PinToken] = [:]

    init(
        transport: any HTTPTransport,
        session: Session,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.transport = transport
        self.session = session
        self.now = now
        self.sleep = sleep
    }

    /// Swaps in a fresh session after logging in again (keeps the sdp map, drops PIN tokens).
    func update(session: Session) {
        self.session = session
        pinTokens.removeAll()
    }

    // MARK: - Vehicles

    func vehicles() async throws(UconnectError) -> [VehicleSummary] {
        let data = try await json(
            "GET", UconnectBrand.api, "/v4/accounts/{uid}/vehicles/",
            query: [("stage", "ALL"), ("sdp", "ALL"), ("brand", UconnectBrand.brandCode)],
            what: "vehicles")
        guard let list = UconnectHTTP.object(data)?["vehicles"] as? [Any] else {
            throw UconnectError.unexpected("vehicles: no vehicles in response")
        }

        var result: [VehicleSummary] = []
        for item in list {
            guard let v = item as? [String: Any], let vin = v["vin"] as? String, !vin.isEmpty else { continue }
            if let sdp = v["sdp"] as? String, !sdp.isEmpty {
                sdpByVIN[vin] = sdp
            }
            result.append(VehicleSummary(
                vin: vin,
                nickname: v["nickname"] as? String,
                services: enabledServices(v["services"])))
        }
        return result
    }

    /// Detailed status (`vehicleInfo`, `evInfo`). Tries v3 then v4 (or the version that
    /// worked last for this VIN), moving on after HTTP 400/404/502.
    func info(vin: String) async throws(UconnectError) -> Data {
        var versions = Self.statusVersions
        if let preferred = statusVersionByVIN[vin], let index = versions.firstIndex(of: preferred) {
            versions.remove(at: index)
            versions.insert(preferred, at: 0)
        }

        for (i, version) in versions.enumerated() {
            let (status, data) = try await request("GET", UconnectBrand.api, vehiclePath(version, vin, "status/"))
            if status >= 400 {
                if [400, 404, 502].contains(status) && i < versions.count - 1 { continue }
                throw UconnectError.unexpected("status: HTTP \(status)")
            }
            let body = try validated(data, what: "status")
            statusVersionByVIN[vin] = version
            return body
        }
        throw UconnectError.unexpected("status: no version")
    }

    /// Doors, windows, liftgate, engine, climate…
    func remoteStatus(vin: String) async throws(UconnectError) -> Data {
        try await json("GET", UconnectBrand.api, vehiclePath("v1", vin, "remote/status/"), what: "remote status")
    }

    /// Last known location.
    func location(vin: String) async throws(UconnectError) -> Data {
        try await json("GET", UconnectBrand.api, vehiclePath("v1", vin, "location/lastknown/"), what: "location")
    }

    // MARK: - Commands

    /// Sends `cmd` and returns once the car reports success. Polls `last-status` every 3 s;
    /// `.commandFailed` on a failure status, `.timeout` after 60 s.
    func send(_ cmd: JeepCommand, vin: String, pin: String) async throws(UconnectError) {
        let sdp = sdpByVIN[vin] ?? Self.defaultSDP
        let pinAuth = try await pinToken(sdp: sdp, pin: pin)

        let (status, data) = try await request(
            "POST", UconnectBrand.api, vehiclePath(cmd.apiVersion, vin, cmd.urlSuffix),
            body: ["command": cmd.rawValue, "pinAuth": pinAuth])
        if status == 401 || status == 403 {
            pinTokens[sdp] = nil  // the PIN token may be stale; get a fresh one next time
        }
        if status >= 400 {
            throw UconnectError.unexpected("command: HTTP \(status)")
        }
        let correlationID = try Self.correlationID(data)

        let started = self.now()
        while true {
            do {
                try await self.sleep(Self.pollInterval)
            } catch {
                throw UconnectError.unexpected("cancelled")
            }

            if let succeeded = try await pollOnce(vin: vin, correlationID: correlationID) {
                if succeeded { return }
                throw UconnectError.commandFailed
            }

            if self.now().timeIntervalSince(started) >= Self.commandTimeout {
                throw UconnectError.timeout
            }
        }
    }

    /// `pin_auth`: exchanges the PIN (base64) for a `pinAuth` token, cached per sdp
    /// until its `expiry` (a lifetime in ms) less 30 s.
    private func pinToken(sdp: String, pin: String) async throws(UconnectError) -> String {
        if let cached = pinTokens[sdp], self.now() < cached.validUntil {
            return cached.token
        }

        let (status, data) = try await request(
            "POST", UconnectBrand.mfa, "/v1/accounts/{uid}/\(Self.pathSegment(sdp))/pin/authenticate/",
            body: ["pin": Data(pin.utf8).base64EncodedString()])
        if (400..<500).contains(status) {
            throw UconnectError.badPin
        }
        if status >= 400 {
            throw UconnectError.unexpected("pin: HTTP \(status)")
        }

        guard let token = UconnectHTTP.object(data)?["token"] as? String, !token.isEmpty else {
            throw UconnectError.badPin
        }
        if let expiryMS = UconnectHTTP.double(UconnectHTTP.object(data)?["expiry"]),
           expiryMS / 1000 > Self.pinTokenMargin {
            pinTokens[sdp] = PinToken(
                token: token,
                validUntil: self.now().addingTimeInterval(expiryMS / 1000 - Self.pinTokenMargin))
        }
        return token
    }

    /// One `last-status` poll: true/false once the car reports a result, nil while pending.
    /// Transient errors count as pending (the poll goes on until the timeout); an expired
    /// session does not.
    private func pollOnce(vin: String, correlationID: String) async throws(UconnectError) -> Bool? {
        let path = vehiclePath("v1", vin, "remote/\(Self.pathSegment(correlationID))/last-status/")
        let response: (status: Int, data: Data)
        do throws(UconnectError) {
            response = try await request("GET", UconnectBrand.api, path)
        } catch {
            if error == .sessionExpired { throw error }
            return nil
        }
        guard response.status < 400, let r = UconnectHTTP.object(response.data) else { return nil }
        let reported = (r["status"] as? String) ?? (r["responseStatus"] as? String)
        guard let status = reported?.lowercased() else { return nil }
        if Self.succeeded.contains(status) { return true }
        if Self.failed.contains(status) { return false }
        return nil
    }

    /// `_correlation_id`: the ID of an accepted command, or `.commandFailed`.
    private nonisolated static func correlationID(_ data: Data) throws(UconnectError) -> String {
        let r = UconnectHTTP.object(data) ?? [:]
        let status = (r["responseStatus"] as? String) ?? (r["requestStatus"] as? String)
        guard let id = r["correlationId"] as? String, !id.isEmpty,
              !rejected.contains(status?.lowercased() ?? "")
        else { throw UconnectError.commandFailed }
        return id
    }

    // MARK: - Requests

    private func vehiclePath(_ version: String, _ vin: String, _ suffix: String) -> String {
        "/\(version)/accounts/{uid}/vehicles/\(Self.pathSegment(vin))/\(suffix)"
    }

    private nonisolated static func pathSegment(_ s: String) -> String {
        UconnectHTTP.encode(s)
    }

    /// A request that must succeed with a JSON object (or an empty body, returned as `{}`).
    private func json(
        _ method: String,
        _ endpoint: UconnectEndpoint,
        _ path: String,
        query: [(String, String)] = [],
        what: String
    ) async throws(UconnectError) -> Data {
        let (status, data) = try await request(method, endpoint, path, query: query)
        if status >= 400 {
            throw UconnectError.unexpected("\(what): HTTP \(status)")
        }
        return try validated(data, what: what)
    }

    private func validated(_ data: Data, what: String) throws(UconnectError) -> Data {
        if data.isEmpty { return Data("{}".utf8) }
        guard UconnectHTTP.object(data) != nil else {
            throw UconnectError.unexpected("\(what): expected a JSON object")
        }
        return data
    }

    /// `API.request`: signs and sends one call. Returns any HTTP status; throws only
    /// `.network`, and `.sessionExpired` when the credentials are (about to be) expired.
    private func request(
        _ method: String,
        _ endpoint: UconnectEndpoint,
        _ path: String,
        query: [(String, String)] = [],
        body: [String: String]? = nil
    ) async throws(UconnectError) -> (status: Int, data: Data) {
        let current = self.now()
        if current >= session.expiresAt.addingTimeInterval(-Self.sessionMargin) {
            throw UconnectError.sessionExpired
        }

        let fullPath = path.replacingOccurrences(of: "{uid}", with: Self.pathSegment(session.uid))
        var urlString = endpoint.url + fullPath
        if !query.isEmpty {
            urlString += "?" + UconnectHTTP.query(query)
        }
        guard let url = URL(string: urlString) else {
            throw UconnectError.unexpected("bad URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        for (name, value) in UconnectHTTP.apiHeaders(key: endpoint.key) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.httpBody = UconnectHTTP.body(body)
        }
        SigV4.sign(&request, credentials: session.aws, region: UconnectBrand.region, now: current)

        let (data, response) = try await UconnectHTTP.send(request, via: transport)
        let status = response.statusCode
        if Self.isExpiredTokenError(status: status, data: data) {
            throw UconnectError.sessionExpired
        }
        return (status, data)
    }

    /// `_is_expired_token_error`: HTTP 401/403 whose message mentions an expired token or signature.
    private nonisolated static func isExpiredTokenError(status: Int, data: Data) -> Bool {
        guard status == 401 || status == 403 else { return false }
        let message: String
        if let object = UconnectHTTP.object(data) {
            message = (object["message"] as? String) ?? ""
        } else {
            message = String(decoding: data, as: UTF8.self)
        }
        let lower = message.lowercased()
        return lower.contains("expired") && (lower.contains("token") || lower.contains("signature"))
    }
}
