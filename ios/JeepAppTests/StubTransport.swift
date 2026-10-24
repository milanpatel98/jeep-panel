import Foundation
import Synchronization
@testable import JeepApp

/// One queued canned response: used when `match` accepts the outgoing request.
nonisolated struct StubResponse: Sendable {
    let match: @Sendable (URLRequest) -> Bool
    let status: Int
    let body: Data

    init(
        match: @escaping @Sendable (URLRequest) -> Bool = { _ in true },
        status: Int = 200,
        body: Data = Data()
    ) {
        self.match = match
        self.status = status
        self.body = body
    }
}

nonisolated struct StubTransportError: Error, CustomStringConvertible {
    let description: String
}

/// Test transport. Each `send` records the request, then consumes the first queued
/// response whose `match` accepts it; throws if none does.
nonisolated final class StubTransport: HTTPTransport {
    private struct State {
        var queue: [StubResponse]
        var sent: [URLRequest] = []
    }

    private let state: Mutex<State>

    init(_ responses: [StubResponse] = []) {
        state = Mutex(State(queue: responses))
    }

    var sent: [URLRequest] {
        state.withLock { $0.sent }
    }

    func enqueue(_ response: StubResponse) {
        state.withLock { $0.queue.append(response) }
    }

    func enqueue(
        status: Int = 200,
        body: Data = Data(),
        match: @escaping @Sendable (URLRequest) -> Bool = { _ in true }
    ) {
        enqueue(StubResponse(match: match, status: status, body: body))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response: StubResponse? = state.withLock { state in
            state.sent.append(request)
            guard let index = state.queue.firstIndex(where: { $0.match(request) }) else {
                return nil
            }
            return state.queue.remove(at: index)
        }
        guard let response else {
            throw StubTransportError(
                description: "No stubbed response for \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "?")")
        }
        let url = request.url ?? URL(fileURLWithPath: "/")
        guard let http = HTTPURLResponse(
            url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: nil)
        else { throw URLError(.badServerResponse) }
        return (response.body, http)
    }
}

private final class FixtureBundleToken {}

/// Loads `Fixtures/<name>.json` from the test bundle.
nonisolated enum Fixture {
    static func data(_ name: String) -> Data {
        let bundle = Bundle(for: FixtureBundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url)
        else {
            preconditionFailure("Missing fixture Fixtures/\(name).json in test bundle")
        }
        return data
    }
}
