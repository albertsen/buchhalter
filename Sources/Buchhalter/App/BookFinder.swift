import SwiftUI
import BuchhalterCore

/// Find Synopsis, shared by the book's row menu and the detail's cover menu.
/// The running books are kept in `WindowModel.findingSynopsis`, so both menus
/// disable the item for a book while its search runs.
@MainActor
enum BookFinder {
    /// Asks the sources that are on with the book's ISBN, then its title and
    /// authors, preferring a text in the book's language, and saves the
    /// synopsis as one undo step. A synopsis typed meanwhile wins. Nothing
    /// found and no source reached each end in their alert.
    static func findSynopsis(for book: Book, lookup: BookLookup, sources: BookSources, library: Library?, model: WindowModel) {
        let queries = LookupQuery.coverQueries(for: BookDraft(book: book))
        guard !queries.isEmpty, !model.findingSynopsis.contains(book.id) else { return }
        let language = book.language
        let id = book.id
        model.findingSynopsis.insert(id)
        Task {
            defer { model.findingSynopsis.remove(id) }
            do {
                guard let synopsis = try await lookup.findSynopsis(queries, bookLanguage: language) else {
                    model.findAlert = .noSynopsis(suggestsGoogleBooks: sources.suggestsGoogleBooks)
                    return
                }
                guard book.synopsis == nil else { return }
                model.attempt { try library?.setSynopsis(synopsis.text, source: synopsis.source, for: book) }
            } catch is LookupError {
                model.findAlert = .noSourceReached
            } catch {
                // Cancelled: nothing changes.
            }
        }
    }

    /// Whether Find Synopsis can run for the book: it has no synopsis, a
    /// source is on, and it has an ISBN or a title and author to search by.
    static func canFindSynopsis(for book: Book, sources: BookSources) -> Bool {
        book.synopsis == nil && sources.hasActiveSource
            && !LookupQuery.coverQueries(for: BookDraft(book: book)).isEmpty
    }
}
