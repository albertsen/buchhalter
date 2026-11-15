import Foundation
import Testing
@testable import BuchhalterCore

@MainActor
struct MissingCoversTests {
    /// A real image, so `CoverImage.normalize` accepts it.
    private let image = fixture("googlebooks-placeholder-300.png")
    private let isbn = "9783935890595"

    private func buddenbrooks(_ t: TestLibrary, isbn: String? = nil) throws -> Book {
        try t.add("Buddenbrooks", by: ["Thomas Mann"], isbn: isbn ?? self.isbn)
    }

    @Test func theISBNIsAskedAtEverySourceBeforeTitleAndAuthor() async throws {
        let t = try TestLibrary()
        let book = try buddenbrooks(t)
        // DNB only has a title match (another edition); Open Library has the ISBN.
        let dnb = FakeLookupService(.dnb, records: [makeRecord("Buddenbrooks", isbn: ["9780000000001"])], covers: [.large: image])
        let ol = FakeLookupService(.openLibrary, records: [makeRecord("Buddenbrooks", isbn: [isbn], source: .openLibrary)], covers: [.large: image])
        let outcome = try await MissingCovers.search(for: book, using: BookLookup(services: [dnb, ol]))
        guard case .found(_, let source, let byISBN) = outcome else { Issue.record("no cover: \(outcome)"); return }
        #expect(source == .openLibrary && byISBN)
    }

    @Test func titleAndAuthorAreTheFallback() async throws {
        let t = try TestLibrary()
        let book = try buddenbrooks(t)
        let dnb = FakeLookupService(.dnb, records: [makeRecord("Buddenbrooks", isbn: ["9780000000001"])], covers: [.large: image])
        let outcome = try await MissingCovers.search(for: book, using: BookLookup(services: [dnb, FakeLookupService(.openLibrary)]))
        guard case .found(_, let source, let byISBN) = outcome else { Issue.record("no cover: \(outcome)"); return }
        #expect(source == .dnb && !byISBN)
    }

    @Test func sourcesAreAskedInTheGivenOrder() async throws {
        let t = try TestLibrary()
        let book = try buddenbrooks(t)
        let record = [makeRecord("Buddenbrooks", isbn: [isbn])]
        let dnb = FakeLookupService(.dnb, records: record, covers: [.large: image])
        let ol = FakeLookupService(.openLibrary, records: record, covers: [.large: image])
        let outcome = try await MissingCovers.search(for: book, using: BookLookup(services: [ol, dnb]))
        guard case .found(_, let source, _) = outcome else { Issue.record("no cover: \(outcome)"); return }
        #expect(source == .openLibrary)
        #expect(dnb.searchCount == 0)
    }

    @Test func answersWithoutACoverAreNotFound() async throws {
        let t = try TestLibrary()
        let book = try buddenbrooks(t)
        let outcome = try await MissingCovers.search(
            for: book, using: BookLookup(services: [FakeLookupService(.dnb), FakeLookupService(.openLibrary)])
        )
        #expect(outcome == .notFound)
    }

    @Test func oneUnreachableSourceIsSkippedAndAllUnreachableIsReported() async throws {
        let t = try TestLibrary()
        let book = try buddenbrooks(t)
        let down = FakeLookupService(.dnb, failing: LookupError.unreachable(.dnb))
        let ol = FakeLookupService(.openLibrary, records: [makeRecord("Buddenbrooks", isbn: [isbn], source: .openLibrary)], covers: [.large: image])
        let skipped = try await MissingCovers.search(for: book, using: BookLookup(services: [down, ol]))
        guard case .found(_, let source, _) = skipped else { Issue.record("no cover: \(skipped)"); return }
        #expect(source == .openLibrary)

        let olDown = FakeLookupService(.openLibrary, failing: LookupError.unreachable(.openLibrary))
        let none = try await MissingCovers.search(for: book, using: BookLookup(services: [down, olDown]))
        #expect(none == .unreachable)
    }

    @Test func aBookWithoutISBNOrAuthorHasNothingToSearch() async throws {
        let t = try TestLibrary()
        let book = try t.add("Untitled notes")
        let outcome = try await MissingCovers.search(for: book, using: BookLookup(services: [FakeLookupService(.dnb)]))
        #expect(outcome == .nothingToSearch)
    }

    @Test func booksWithoutACoverAreListedOldestFirst() throws {
        let t = try TestLibrary()
        let newer = try t.add("B")
        newer.addedAt = date(2026, 3, 1)
        let older = try t.add("A")
        older.addedAt = date(2020, 1, 1)
        let covered = try t.add("C")
        covered.coverImage = image
        #expect(try MissingCovers.books(in: t.context).map(\.title) == ["A", "B"])
    }

    @Test func eachSourceMakesItsService() {
        let keys = FakeSecretStore("k")
        for source in [LookupSource.dnb, .openLibrary, .googleBooks] {
            #expect(source.makeService(keys: keys).source == source)
        }
    }
}
