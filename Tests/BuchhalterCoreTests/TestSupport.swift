import Foundation
import SwiftData
@testable import BuchhalterCore

/// An in-memory library. Keep `container` alive for as long as the context is used.
@MainActor
struct TestLibrary {
    let container: ModelContainer
    let library: Library
    let undo: UndoManager?

    var context: ModelContext { library.context }

    init(undo: Bool = false) throws {
        container = try LibraryContainer.inMemory()
        let context = container.mainContext
        if undo {
            let manager = UndoManager()
            manager.groupsByEvent = false
            self.undo = manager
        } else {
            self.undo = nil
        }
        // The context's own undoManager stays nil: Library does the undo.
        library = Library(context: context, undoManager: self.undo)
    }

    @discardableResult
    func add(
        _ title: String, by authors: [String] = [], status: DraftStatus? = .wantToRead,
        year: Int? = nil, pages: Int? = nil, isbn: String = "", collections: [UUID] = [],
        started: Date? = nil, finished: Date? = nil, rating: Int? = nil, notes: String = ""
    ) throws -> Book {
        var draft = BookDraft()
        draft.title = title
        draft.authors = authors.map { library.suggestedAuthor(for: $0) }
        draft.status = status
        draft.yearText = year.map(String.init) ?? ""
        draft.pagesText = pages.map(String.init) ?? ""
        draft.isbnText = isbn
        draft.collectionIDs = collections
        draft.startedAt = started
        if let finished { draft.finishedAt = finished }
        draft.rating = rating
        draft.notes = notes
        return try library.addBook(draft)
    }
}

func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    return Calendar.current.date(from: components) ?? .distantPast
}
