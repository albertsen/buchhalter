import Foundation
@testable import BuchhalterCore

/// A recorded service response from `Fixtures/`, read through `#filePath`
/// (the fixtures are not package resources).
func fixture(_ name: String, file: StaticString = #filePath) -> Data {
    let url = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().appending(path: "Fixtures/\(name)")
    return (try? Data(contentsOf: url)) ?? Data()
}

/// Answers every request from a closure and records the URLs it was asked for.
/// The tests never touch the network.
actor FakeHTTPClient: HTTPClient {
    typealias Handler = @Sendable (URL) throws -> (Data, Int)

    private let handler: Handler
    private(set) var requested: [URL] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// Always the same body and status.
    init(data: Data, status: Int = 200) {
        handler = { _ in (data, status) }
    }

    func get(_ url: URL, timeout: TimeInterval) async throws -> (Data, Int) {
        requested.append(url)
        return try handler(url)
    }
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
        id: id ?? "\(source == .dnb ? "dnb" : "openlibrary"):\(title)-\(year ?? 0)-\(isbn.first ?? "")",
        source: source, title: title, authors: authors.map { LookupMatching.headingToName($0) },
        year: year, language: language, isbn13s: isbn, isbnDisplay: isbn.first,
        cover: isbn.first.map { .dnb(isbn13: $0) }
    )
}
