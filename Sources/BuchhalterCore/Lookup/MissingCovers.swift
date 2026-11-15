import Foundation
import SwiftData

/// Find Cover for many books at once, for `buchhalter-cli find-covers`. It
/// runs the same search as Find Cover in the detail (the ISBN at every source,
/// then title and author at every source, in the user's order), but one
/// source and one search at a time, so the result names where the cover came
/// from. It changes nothing; the caller stores the cover.
public enum MissingCovers {
    /// What the search for one book found.
    public enum Outcome: Equatable, Sendable {
        /// A normalized cover, the source it came from, and whether the ISBN
        /// found it (a title-and-author match may show another edition).
        case found(Data, source: LookupSource, byISBN: Bool)
        /// At least one source answered, and none had a cover.
        case notFound
        /// No source could be reached for any search.
        case unreachable
        /// Neither a valid ISBN nor a title with an author: nothing to search for.
        case nothingToSearch
    }

    /// The books without a cover, oldest first, so a repeated run with a
    /// limit works through the library in a stable order.
    @MainActor
    public static func books(in context: ModelContext) throws -> [Book] {
        try context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.addedAt), SortDescriptor(\.title)]))
            .filter { $0.coverImage == nil }
    }

    /// Searches one book's cover with `lookup`'s sources.
    ///
    /// - Parameter pause: waited after every request that found nothing, so a
    ///   run over hundreds of books does not flood the free services.
    @MainActor
    public static func search(
        for book: Book, using lookup: BookLookup, pause: Duration = .zero
    ) async throws -> Outcome {
        let queries = LookupQuery.coverQueries(for: BookDraft(book: book))
        guard !queries.isEmpty else { return .nothingToSearch }
        let language = book.language
        var answered = false
        for query in queries {
            for service in lookup.services {
                let single = BookLookup(services: [service], observer: lookup.observer)
                do {
                    if let data = try await single.findCover([query], preferredLanguage: language) {
                        let byISBN = if case .isbn = query { true } else { false }
                        return .found(data, source: service.source, byISBN: byISBN)
                    }
                    answered = true
                } catch is LookupError {
                    // With one service, `findCover` throws only when that
                    // source could not be reached; the next one is asked.
                }
                if pause > .zero { try await Task.sleep(for: pause) }
            }
        }
        return answered ? .notFound : .unreachable
    }
}

extension LookupSource {
    /// The live service for this source. Google Books reads its key from `keys`.
    public func makeService(keys: any SecretStore) -> any BookLookupService {
        switch self {
        case .dnb: DNBService()
        case .openLibrary: OpenLibraryService()
        case .googleBooks: GoogleBooksService(keys: keys)
        }
    }
}
