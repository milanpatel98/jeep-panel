import Foundation
import Testing
@testable import Forx

private nonisolated struct SigV4Fixture: Decodable {
    struct Creds: Decodable {
        let access: String
        let secret: String
        let session: String
    }
    struct Expected: Decodable {
        let authorization: String
        let x_amz_date: String
    }
    struct Req: Decodable {
        let method: String
        let url: String
        let headers: [String: String]
        let body: String
    }
    let creds: Creds
    let expected: Expected
    let now: String
    let region: String
    let service: String
    let request: Req
}

struct SigV4Tests {
    @Test func matchesPyUconnect() throws {
        let fx = try JSONDecoder().decode(SigV4Fixture.self, from: Fixture.data("sigv4_get"))
        let url = try #require(URL(string: fx.request.url))
        let now = try #require(ISO8601DateFormatter().date(from: fx.now))

        var request = URLRequest(url: url)
        request.httpMethod = fx.request.method
        for (name, value) in fx.request.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if !fx.request.body.isEmpty {
            request.httpBody = Data(fx.request.body.utf8)
        }

        let credentials = AWSCredentials(
            accessKeyId: fx.creds.access,
            secretAccessKey: fx.creds.secret,
            sessionToken: fx.creds.session)
        SigV4.sign(&request, credentials: credentials, region: fx.region, service: fx.service, now: now)

        #expect(request.value(forHTTPHeaderField: "X-Amz-Date") == fx.expected.x_amz_date)
        #expect(request.value(forHTTPHeaderField: "Authorization") == fx.expected.authorization)
        #expect(request.value(forHTTPHeaderField: "X-Amz-Security-Token") == fx.creds.session)
    }
}
