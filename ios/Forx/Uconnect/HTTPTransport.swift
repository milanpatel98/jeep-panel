import Foundation

/// The one seam between the Uconnect client and the network. Production uses
/// `URLSessionTransport`; tests use a stub.
nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = URLSessionTransport.makeSession()) {
        self.session = session
    }

    /// Ephemeral, with no URL cache: responses carry the VIN and GPS and are never written to disk.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
