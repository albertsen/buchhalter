import Foundation
import SwiftData
import Testing
@testable import BuchhalterCore

/// Each user action must undo and redo as one step, with a manager that has
/// no run loop (`groupsByEvent = false`), as in unit tests.
@MainActor
struct UndoTests {
    private func checkUndoRedo(
        _ t: TestLibrary, snapshot: () -> String, _ action: () throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let undo = try #require(t.undo, sourceLocation: sourceLocation)
        let before = snapshot()
        try action()
        let after = snapshot()
        #expect(before != after, "the action changed nothing", sourceLocation: sourceLocation)
        #expect(undo.canUndo, sourceLocation: sourceLocation)
        undo.undo()
        t.context.processPendingChanges()
        #expect(snapshot() == before, "undo", sourceLocation: sourceLocation)
        #expect(!undo.canUndo || undo.canRedo, sourceLocation: sourceLocation)
        undo.redo()
        t.context.processPendingChanges()
        #expect(snapshot() == after, "redo", sourceLocation: sourceLocation)
        undo.undo()
        t.context.processPendingChanges()
        #expect(snapshot() == before, "second undo", sourceLocation: sourceLocation)
    }

    /// A text picture of everything the library holds.
    private func snapshot(_ t: TestLibrary) -> String {
        let books = t.library.fetchBooks().sorted { $0.title < $1.title }
        let lines = books.map { book -> String in
            let readings = book.readingsByCreation.map {
                "\($0.statusRaw)/\($0.startedAt?.timeIntervalSince1970 ?? -1)/\($0.endedAt?.timeIntervalSince1970 ?? -1)/\($0.rating ?? 0)/\($0.notes ?? "")"
            }.joined(separator: ";")
            let authors = book.orderedAuthors.map { "\($0.name)=\($0.sortName)" }.joined(separator: ";")
            let collections = (book.collections ?? []).map(\.name).sorted().joined(separator: ";")
            return "\(book.title)|\(book.year ?? 0)|\(authors)|\(readings)|\(collections)|\(book.coverImage?.count ?? 0)"
        }
        let collections = t.library.fetchCollections().map { "\($0.name)#\($0.sortIndex)" }
        return (lines + collections).joined(separator: "\n")
    }

    @Test func addBookUndoes() throws {
        let t = try TestLibrary(undo: true)
        try checkUndoRedo(t, snapshot: { snapshot(t) }) {
            try t.add("A", by: ["Thomas Mann"], status: .reading)
        }
        #expect(try t.context.fetchCount(FetchDescriptor<Authorship>()) == 0)
    }

    @Test func editBookUndoes() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("A", by: ["Thomas Mann"], year: 1900)
        try checkUndoRedo(t, snapshot: { snapshot(t) }) {
            var draft = BookDraft(book: book)
            draft.title = "A2"
            draft.yearText = "1901"
            draft.authors = [t.library.suggestedAuthor(for: "Erika Mann")]
            try t.library.updateBook(book, with: draft)
        }
    }

    @Test func readingActionsUndo() throws {
        let t = try TestLibrary(undo: true)
        let a = try t.add("A", status: .reading, started: date(2026, 1, 1))
        try checkUndoRedo(t, snapshot: { snapshot(t) }) {
            try t.library.finishReading(a, on: date(2026, 2, 1), rating: 4, notes: "ok")
        }
        let b = try t.add("B", status: .reading, started: date(2026, 1, 1))
        try checkUndoRedo(t, snapshot: { snapshot(t) }) {
            try t.library.abandonReading(b, on: date(2026, 2, 1), notes: nil)
        }
        let c = try t.add("C", status: .read, started: date(2026, 1, 1), finished: date(2026, 2, 1))
        try checkUndoRedo(t, snapshot: { snapshot(t) }) { try t.library.readAgain(c) }
        let reading = try #require(a.currentReading)
        try checkUndoRedo(t, snapshot: { snapshot(t) }) {
            try t.library.updateReading(reading, startedAt: date(2026, 1, 2), endedAt: date(2026, 2, 3), rating: 2, notes: nil)
        }
        try checkUndoRedo(t, snapshot: { snapshot(t) }) { try t.library.deleteReading(reading) }
    }

    @Test func deleteBookWithCascadeUndoes() throws {
        let t = try TestLibrary(undo: true)
        let collection = try t.library.createCollection(named: "Owned")
        let book = try t.add("A", by: ["Thomas Mann", "Erika Mann"], status: .read,
                             collections: [collection.id], started: date(2026, 1, 1), finished: date(2026, 2, 1), rating: 5)
        try t.library.readAgain(book)
        try checkUndoRedo(t, snapshot: { snapshot(t) }) { try t.library.deleteBook(book) }
        let restored = try #require(t.library.fetchBooks().first)
        #expect(restored.readings?.count == 2)
        #expect(restored.orderedAuthors.map(\.name) == ["Thomas Mann", "Erika Mann"])
        #expect(restored.collections?.count == 1)
    }

    @Test func collectionChangesUndo() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("A")
        try checkUndoRedo(t, snapshot: { snapshot(t) }) { try t.library.createCollection(named: "One") }
        try t.library.createCollection(named: "One")
        let collection = try t.library.createCollection(named: "Two")
        try checkUndoRedo(t, snapshot: { snapshot(t) }) { try t.library.renameCollection(collection, to: "Zwei") }
        try checkUndoRedo(t, snapshot: { snapshot(t) }) {
            try t.library.moveCollections(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        }
        try checkUndoRedo(t, snapshot: { snapshot(t) }) { try t.library.add(book, to: collection) }
        try t.library.add(book, to: collection)
        try checkUndoRedo(t, snapshot: { snapshot(t) }) { try t.library.remove(book, from: collection) }
        try checkUndoRedo(t, snapshot: { snapshot(t) }) { try t.library.deleteCollection(collection) }
        try checkUndoRedo(t, snapshot: { snapshot(t) }) { try t.library.createCollection(named: "Three", adding: book) }
    }

    @Test func deletedCollectionComesBackWithItsSettings() throws {
        let t = try TestLibrary(undo: true)
        let undo = try #require(t.undo)
        let collection = try t.library.createCollection(named: "A")
        let id = collection.id
        try t.library.setViewMode(.grid, for: .collection(id))
        try t.library.deleteCollection(collection)
        undo.undo()
        #expect(t.library.preferences(for: .collection(id)).viewMode == .grid)
    }

    @Test func coverAndSortNameUndo() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("A", by: ["Thomas Mann"])
        try checkUndoRedo(t, snapshot: { snapshot(t) }) { try t.library.setCover(Data([1, 2, 3]), for: book) }
        let author = try #require(book.orderedAuthors.first)
        try checkUndoRedo(t, snapshot: { snapshot(t) }) { try t.library.setSortName("Zzz, Thomas", for: author) }
    }

    @Test func sortAndViewChangesLeaveTheUndoStackAlone() throws {
        let t = try TestLibrary(undo: true)
        let undo = try #require(t.undo)
        try t.library.setViewMode(.grid, for: .all)
        try t.library.setSortLevels(SortLevels(levels: [SortLevel(field: .title)]), for: .all)
        try t.library.resetSort(for: .reading)
        #expect(!undo.canUndo)
        // And the settings survive an undo of an earlier data change.
        try t.add("A")
        undo.undo()
        t.context.processPendingChanges()
        #expect(t.library.preferences(for: .all).viewMode == .grid)
    }

    @Test func actionNamesAreSet() throws {
        let t = try TestLibrary(undo: true)
        try t.add("A")
        #expect(t.undo?.undoActionName == "Add Book")
    }
}
