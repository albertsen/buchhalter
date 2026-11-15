import Foundation

/// The one door to the network for book lookup, so the services can be tested
/// against recorded responses.
public protocol HTTPClient: Sendable {
    /// The body and the HTTP status. Throws on transport errors; a cancelled
    /// task throws `CancellationError` or `URLError.cancelled`.
    func get(_ url: URL, timeout: TimeInterval) async throws -> (Data, Int)
}

/// `URLSession` with an ephemeral configuration: no cookies and no disk
/// cache, so nothing about a lookup stays on disk. Every request names the
/// app, as Open Library asks, without a name or an email address.
public struct URLSessionHTTPClient: HTTPClient {
    public static let userAgent = "Buchhalter/0.1 (personal book app)"

    private let session: URLSession

    public init() {
        session = URLSession(configuration: .ephemeral)
    }

    public func get(_ url: URL, timeout: TimeInterval) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http.statusCode)
    }
}

extension Error {
    /// True for the errors a cancelled task produces.
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
