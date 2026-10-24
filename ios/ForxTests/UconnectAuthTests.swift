import Foundation
import Testing
@testable import Forx

private let gigyaOK = Data(#"{"statusCode": 200, "errorCode": 0}"#.utf8)

private nonisolated func gigyaCall(_ call: String) -> @Sendable (URLRequest) -> Bool {
    { $0.url?.host() == "login-us.jeep.com" && $0.url?.path() == "/\(call)" }
}

private func query(_ request: URLRequest) -> [String: String] {
    guard let url = request.url,
          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return [:] }
    var out: [String: String] = [:]
    for item in items { out[item.name] = item.value ?? "" }
    return out
}

private func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
}

struct UconnectAuthTests {
    // Fake test-only credentials, never real ones.
    private let email = "driver@example.invalid"
    private let password = "fake pass+word&"

    @Test func loginHappyPath() async throws {
        let stub = StubTransport()
        stub.enqueue(body: gigyaOK, match: gigyaCall("accounts.webSdkBootstrap"))
        stub.enqueue(body: Fixture.data("gigya_login"), match: gigyaCall("accounts.login"))
        stub.enqueue(body: Fixture.data("gigya_jwt"), match: gigyaCall("accounts.getJWT"))
        stub.enqueue(body: Fixture.data("token_exchange"), match: { $0.url?.host() == "authz.sdpr-02.fcagcv.com" })
        stub.enqueue(body: Fixture.data("cognito"), match: { $0.url?.host() == "cognito-identity.us-east-1.amazonaws.com" })

        let session = try await UconnectAuth(transport: stub).login(email: email, password: password)

        #expect(session.uid == "uid-fake")
        #expect(session.aws.accessKeyId == "AKIAFAKEACCESSKEY")
        #expect(session.aws.secretAccessKey == "fake-secret-key")
        #expect(session.aws.sessionToken == "fake-session-token")
        #expect(session.expiresAt == Date(timeIntervalSince1970: 1_792_846_800))

        let sent = stub.sent
        #expect(sent.count == 5)
        guard sent.count == 5 else { return }

        // 1. Bootstrap (GET, Gigya API key only)
        #expect(sent[0].httpMethod == "GET")
        #expect(query(sent[0]) == ["apiKey": UconnectBrand.loginAPIKey])

        // 2. accounts.login: everything in the query string, like aiohttp's params=
        #expect(sent[1].httpMethod == "POST")
        let login = query(sent[1])
        #expect(login["loginID"] == email)
        #expect(login["password"] == password)
        #expect(login["APIKey"] == UconnectBrand.loginAPIKey)
        #expect(login["sessionExpiration"] == "300")
        #expect(login["targetEnv"] == "jssdk")
        #expect(login["include"] == "profile,data,emails,subscriptions,preferences")
        // '+' and '&' must be percent-encoded, not sent raw
        #expect(sent[1].url?.absoluteString.contains("fake%20pass%2Bword%26") == true)

        // 3. accounts.getJWT
        #expect(sent[2].httpMethod == "POST")
        #expect(query(sent[2])["login_token"] == "fake-login-token")
        #expect(query(sent[2])["fields"] == UconnectBrand.jwtFields)

        // 4. Token exchange
        #expect(sent[3].url?.absoluteString == "https://authz.sdpr-02.fcagcv.com/v2/cognito/identity/token")
        #expect(sent[3].httpMethod == "POST")
        #expect(sent[3].value(forHTTPHeaderField: "x-api-key") == UconnectBrand.api.key)
        #expect(sent[3].value(forHTTPHeaderField: "locale") == "en_us")
        #expect(try bodyJSON(sent[3])["gigya_token"] as? String == "fake-id-token")

        // 5. Cognito GetCredentialsForIdentity
        #expect(sent[4].url?.absoluteString == "https://cognito-identity.us-east-1.amazonaws.com/")
        #expect(sent[4].value(forHTTPHeaderField: "X-Amz-Target") == "AWSCognitoIdentityService.GetCredentialsForIdentity")
        #expect(sent[4].value(forHTTPHeaderField: "Content-Type") == "application/x-amz-json-1.1")
        let cognito = try bodyJSON(sent[4])
        #expect(cognito["IdentityId"] as? String == "us-east-1:fake-identity-id")
        #expect((cognito["Logins"] as? [String: String])?["cognito-identity.amazonaws.com"] == "fake-openid-token")
    }

    @Test func wrongPasswordIsBadLogin() async {
        let stub = StubTransport()
        stub.enqueue(body: gigyaOK, match: gigyaCall("accounts.webSdkBootstrap"))
        // Gigya answers HTTP 200 and puts the failure in the body.
        stub.enqueue(status: 200, body: Fixture.data("gigya_login_badpassword"), match: gigyaCall("accounts.login"))

        await #expect(throws: UconnectError.badLogin) {
            try await UconnectAuth(transport: stub).login(email: email, password: password)
        }
        #expect(stub.sent.count == 2)
    }

    @Test func otherLoginErrorIsRejected() async {
        let stub = StubTransport()
        stub.enqueue(body: gigyaOK, match: gigyaCall("accounts.webSdkBootstrap"))
        // 403120: account temporarily locked. Any non-zero errorCode from accounts.login stops.
        let locked = Data(#"{"statusCode": 403, "errorCode": 403120, "errorMessage": "Account temporarily locked"}"#.utf8)
        stub.enqueue(status: 200, body: locked, match: gigyaCall("accounts.login"))

        await #expect(throws: UconnectError.loginRejected(403120)) {
            try await UconnectAuth(transport: stub).login(email: email, password: password)
        }
        #expect(stub.sent.count == 2)
    }

    @Test func unreachableIsNetwork() async {
        let stub = StubTransport()  // nothing queued: the stub throws like a dropped connection
        await #expect(throws: UconnectError.network) {
            try await UconnectAuth(transport: stub).login(email: email, password: password)
        }
    }
}
