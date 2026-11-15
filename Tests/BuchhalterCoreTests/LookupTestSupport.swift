import Foundation
@testable import BuchhalterCore

/// A recorded service response from `Fixtures/`, read through `#filePath`
/// (the fixtures are not package resources).
func fixture(_ name: String, file: StaticString = #filePath) -> Data {
    let url = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().appending(path: "Fixtures/\(name)")
    return (try? Data(contentsOf: url)) ?? Data()
}

/// Answers every request from a closure and records the URLs and headers it
/// was asked for. The tests never touch the network.
actor FakeHTTPClient: HTTPClient {
    typealias Handler = @Sendable (URL) throws -> (Data, Int)

    private let handler: Handler
    private(set) var requested: [URL] = []
    private(set) var requestedHeaders: [[String: String]] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// Always the same body and status.
    init(data: Data, status: Int = 200) {
        handler = { _ in (data, status) }
    }

    func get(_ url: URL, headers: [String: String], timeout: TimeInterval) async throws -> (Data, Int) {
        requested.append(url)
        requestedHeaders.append(headers)
        return try handler(url)
    }
}

/// A secret store in memory. `read` can fail, and counts its calls.
final class FakeSecretStore: SecretStore, @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private var secret: String?
    private var reads = 0
    private let failing: Bool

    init(_ secret: String? = nil, failing: Bool = false) {
        self.secret = secret
        self.failing = failing
    }

    var readCount: Int { lock.withLock { reads } }

    func read() async throws -> String? {
        lock.withLock { reads += 1 }
        if failing { throw Failure() }
        return lock.withLock { secret }
    }

    func save(_ secret: String) async throws { lock.withLock { self.secret = secret } }
    func delete() async throws { lock.withLock { secret = nil } }
    func exists() async -> Bool { lock.withLock { secret != nil } }
    func suffix() async -> String? { lock.withLock { secret.map { String($0.suffix(4)) } } }
}

/// A service with canned results, for the coordinator tests.
final class FakeLookupService: BookLookupService, @unchecked Sendable {
    let source: LookupSource
    private let lock = NSLock()
    private var calls = 0
    private let outcome: Result<LookupResponse, Error>
    private let covers: [CoverSize: Data]
    private let delay: Duration?

    init(
        _ source: LookupSource, records: [LookupRecord] = [], total: Int? = nil,
        failing error: Error? = nil, covers: [CoverSize: Data] = [:], delay: Duration? = nil
    ) {
        self.source = source
        self.covers = covers
        self.delay = delay
        if let error {
            outcome = .failure(error)
        } else {
            outcome = .success(LookupResponse(records: records, totalCount: total ?? records.count))
        }
    }

    var searchCount: Int {
        lock.withLock { calls }
    }

    func search(_ query: LookupQuery) async throws -> LookupResponse {
        lock.withLock { calls += 1 }
        if let delay { try await Task.sleep(for: delay) }
        return try outcome.get()
    }

    func coverData(for reference: CoverReference, size: CoverSize) async -> Data? {
        covers[size]
    }
}

/// A short record for tests that do not need the fixtures.
func makeRecord(
    _ title: String, by authors: [String] = ["Thomas Mann"], year: Int? = nil, language: String? = "de",
    isbn: [String] = [], source: LookupSource = .dnb, id: String? = nil
) -> LookupRecord {
    LookupRecord(
        id: id ?? "\(source.rawValue.lowercased()):\(title)-\(year ?? 0)-\(isbn.first ?? "")",
        source: source, title: title, authors: authors.map { LookupMatching.headingToName($0) },
        year: year, language: language, isbn13s: isbn, isbnDisplay: isbn.first,
        cover: isbn.first.map { .dnb(isbn13: $0) }
    )
}
