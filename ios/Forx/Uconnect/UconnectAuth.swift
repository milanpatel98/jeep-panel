import Foundation

/// A logged-in Uconnect session: the Gigya account UID (part of most API paths)
/// and temporary AWS credentials from Cognito.
nonisolated struct Session: Codable, Sendable {
    var uid: String
    var aws: AWSCredentials
    var expiresAt: Date
}

nonisolated enum UconnectError: Error, Equatable {
    case badLogin
    case badPin
    case network
    case timeout
    case commandFailed
    case unexpected(String)
    /// The AWS credentials expired (locally or as reported by the API): log in again.
    case sessionExpired
}

/// An API Gateway endpoint: base URL and the matching `x-api-key`.
nonisolated struct UconnectEndpoint: Sendable {
    let url: String
    let key: String
}

/// `JEEP_US` from py-uconnect's `brands.py`. These are the public keys of
/// Jeep's own web portal, not account secrets.
nonisolated enum UconnectBrand {
    static let region = "us-east-1"
    static let loginAPIKey = "3_5qxvrevRPG7--nEXe6huWdVvF5kV7bmmJcyLdaTJ8A45XUYpaR398QNeHkd7EB1X"
    static let loginURL = "https://login-us.jeep.com"
    static let tokenURL = "https://authz.sdpr-02.fcagcv.com/v2/cognito/identity/token"
    static let api = UconnectEndpoint(
        url: "https://channels.sdpr-02.fcagcv.com",
        key: "OgNqp2eAv84oZvMrXPIzP8mR8a6d9bVm1aaH9LqU")
    static let mfa = UconnectEndpoint(
        url: "https://mfa.fcl-02.fcagcv.com",
        key: "fNQO6NjR1N6W0E5A6sTzR3YY4JGbuPv48Nj9aZci")
    static let locale = "en_us"
    /// Value of the `brand` filter when listing vehicles.
    static let brandCode = "ALL"

    /// `GIGYA_PARAMS` in `auth.py`, in order.
    static let gigyaParams: [(String, String)] = [
        ("targetEnv", "jssdk"),
        ("loginMode", "standard"),
        ("sdk", "js_latest"),
        ("authMode", "cookie"),
        ("sdkBuild", "12234"),
        ("format", "json"),
    ]

    static let jwtFields =
        "profile.firstName,profile.lastName,profile.email,country,locale,data.disclaimerCodeGSDP"
}

/// HTTP helpers shared by login and the API client (`_http.py`).
nonisolated enum UconnectHTTP {
    /// The API keys belong to the web portal, so requests look like a desktop browser.
    static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    /// `api_headers`: headers expected by the Uconnect API gateways.
    static func apiHeaders(key: String) -> [String: String] {
        let requestID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased().prefix(16))
        return [
            "User-Agent": userAgent,
            "Content-Type": "application/json",
            "x-clientapp-name": "CWP",
            "x-clientapp-version": "1.0",
            "x-originator-type": "web",
            "clientrequestid": requestID,
            "x-api-key": key,
            "locale": UconnectBrand.locale,
        ]
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")

    /// Percent-encodes everything but RFC 3986 unreserved characters, so '+', '&'
    /// and '=' in a password survive the query string.
    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    static func query(_ items: [(String, String)]) -> String {
        items.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
    }

    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func body(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
            ?? Data()
    }

    /// Sends through the transport; any transport failure is `.network`.
    static func send(
        _ request: URLRequest, via transport: any HTTPTransport
    ) async throws(UconnectError) -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch {
            throw UconnectError.network
        }
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

/// Login flow ported from py-uconnect's `auth.py`:
/// Gigya bootstrap → accounts.login → accounts.getJWT → token exchange → Cognito credentials.
/// Nothing here is logged: the email, password and every token are secrets.
nonisolated struct UconnectAuth: UconnectAuthProtocol {
    /// Gigya error code for a wrong email or password.
    static let invalidLoginErrorCode = 403042

    private let transport: any HTTPTransport

    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    func login(email: String, password: String) async throws(UconnectError) -> Session {
        // Gigya keeps state in cookies between its calls; tracked here, not in a shared jar.
        var cookies: [String: String] = [:]

        _ = try await gigya("GET", "accounts.webSdkBootstrap", [("apiKey", UconnectBrand.loginAPIKey)], &cookies)

        let loginParams = UconnectBrand.gigyaParams + [
            ("APIKey", UconnectBrand.loginAPIKey),
            ("loginID", email),
            ("password", password),
            ("sessionExpiration", "300"),
            ("include", "profile,data,emails,subscriptions,preferences"),
        ]
        let login = try await gigya("POST", "accounts.login", loginParams, &cookies)
        guard let uid = login["UID"] as? String,
              let sessionInfo = login["sessionInfo"] as? [String: Any],
              let loginToken = sessionInfo["login_token"] as? String
        else { throw UconnectError.unexpected("accounts.login: unexpected response") }

        let jwtParams = UconnectBrand.gigyaParams + [
            ("APIKey", UconnectBrand.loginAPIKey),
            ("login_token", loginToken),
            ("fields", UconnectBrand.jwtFields),
        ]
        let jwt = try await gigya("POST", "accounts.getJWT", jwtParams, &cookies)
        guard let idToken = jwt["id_token"] as? String else {
            throw UconnectError.unexpected("accounts.getJWT: no id_token")
        }

        let (identityID, openIDToken) = try await exchangeToken(idToken)
        let (aws, expiresAt) = try await cognitoCredentials(identityID: identityID, token: openIDToken)
        return Session(uid: uid, aws: aws, expiresAt: expiresAt)
    }

    // MARK: - Steps

    /// `_gigya`: parameters go in the query string (aiohttp `params=`) for GET and POST alike.
    /// Gigya answers HTTP 200 and reports failures in the body's `statusCode`/`errorCode`.
    private func gigya(
        _ method: String,
        _ call: String,
        _ params: [(String, String)],
        _ cookies: inout [String: String]
    ) async throws(UconnectError) -> [String: Any] {
        guard let url = URL(string: "\(UconnectBrand.loginURL)/\(call)?\(UconnectHTTP.query(params))") else {
            throw UconnectError.unexpected("\(call): bad URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue(UconnectHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        if !cookies.isEmpty {
            let header = cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await UconnectHTTP.send(request, via: transport)
        for cookie in Self.cookies(from: response, url: url) {
            cookies[cookie.name] = cookie.value
        }

        guard response.statusCode == 200, let r = UconnectHTTP.object(data) else {
            throw UconnectError.unexpected("\(call): HTTP \(response.statusCode)")
        }

        let statusCode = UconnectHTTP.int(r["statusCode"])
        let errorCode = UconnectHTTP.int(r["errorCode"]) ?? 0
        if statusCode != 200 || errorCode != 0 {
            if errorCode == Self.invalidLoginErrorCode {
                throw UconnectError.badLogin
            }
            throw UconnectError.unexpected("\(call) failed: errorCode \(errorCode)")
        }
        return r
    }

    /// `_exchange_token`: Gigya JWT → Cognito identity ID and OpenID token.
    private func exchangeToken(_ idToken: String) async throws(UconnectError) -> (String, String) {
        guard let url = URL(string: UconnectBrand.tokenURL) else {
            throw UconnectError.unexpected("token exchange: bad URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        for (name, value) in UconnectHTTP.apiHeaders(key: UconnectBrand.api.key) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = UconnectHTTP.body(["gigya_token": idToken])

        let (data, response) = try await UconnectHTTP.send(request, via: transport)
        let status = response.statusCode
        if (400..<500).contains(status) {
            throw UconnectError.unexpected("token exchange rejected: HTTP \(status)")
        }
        let r = UconnectHTTP.object(data)
        guard status == 200,
              let token = r?["Token"] as? String, !token.isEmpty,
              let identityID = r?["IdentityId"] as? String, !identityID.isEmpty
        else { throw UconnectError.unexpected("token exchange failed: HTTP \(status)") }
        return (identityID, token)
    }

    /// `_cognito_credentials`: unsigned Cognito GetCredentialsForIdentity call.
    private func cognitoCredentials(
        identityID: String, token: String
    ) async throws(UconnectError) -> (AWSCredentials, Date) {
        guard let url = URL(string: "https://cognito-identity.\(UconnectBrand.region).amazonaws.com/") else {
            throw UconnectError.unexpected("Cognito: bad URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityService.GetCredentialsForIdentity", forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = UconnectHTTP.body([
            "IdentityId": identityID,
            "Logins": ["cognito-identity.amazonaws.com": token],
        ])

        let (data, response) = try await UconnectHTTP.send(request, via: transport)
        let parsed = UconnectHTTP.object(data)
        guard response.statusCode == 200, let r = parsed else {
            let type = (parsed?["__type"] as? String) ?? ""
            throw UconnectError.unexpected("Cognito: HTTP \(response.statusCode) \(type)")
        }

        guard let c = r["Credentials"] as? [String: Any],
              let accessKeyId = c["AccessKeyId"] as? String,
              let secretKey = c["SecretKey"] as? String,
              let sessionToken = c["SessionToken"] as? String,
              let expiration = UconnectHTTP.double(c["Expiration"])
        else { throw UconnectError.unexpected("Cognito: unexpected response") }

        let aws = AWSCredentials(accessKeyId: accessKeyId, secretAccessKey: secretKey, sessionToken: sessionToken)
        return (aws, Date(timeIntervalSince1970: expiration))
    }

    private static func cookies(from response: HTTPURLResponse, url: URL) -> [HTTPCookie] {
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                fields[key] = value
            }
        }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
    }
}
