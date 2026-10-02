import Foundation

/// The one thing the network clients need from the network: send a request, get the answer. Tests
/// hand in a stub, so nothing here ever touches a socket.
public protocol HTTPTransport: Sendable {
    /// Returns the body and the response. A status outside 2xx is still a response, not a throw;
    /// the caller decides what an error status means for it. Transport failures (no network,
    /// timeout) throw the `URLError` as is.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// A transport that answers from a closure. It lives in the library, not the test target, because
/// UI scenarios launch the app itself with stubbed dependencies (no network, no iCloud).
public struct StubHTTPTransport: HTTPTransport {
    /// Gets the request, returns the body and the status code, or throws like a failed connection.
    public typealias Handler = @Sendable (URLRequest) throws -> (Data, Int)

    private let handler: Handler

    public init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// Always the same answer.
    public init(status: Int = 200, body: Data = Data()) {
        self.init { _ in (body, status) }
    }

    /// Always the same failure, e.g. `URLError(.notConnectedToInternet)`.
    public init(error: any Error) {
        self.init { _ in throw error }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, status) = try handler(request)
        let url = request.url ?? URL(fileURLWithPath: "/")
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}

/// The real network, through `URLSession`.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
