import Foundation
import SwiftData
import Testing
@testable import BuchhalterCore

/// SwiftData's own undo leaves attribute changes unsaved on macOS 27.2: the
/// value reverts in memory, then a fetch brings the old one back. These tests
/// check what `Library`'s undo really writes: the value after a fresh fetch on
/// the main context and as seen from a second `ModelContext`, after undo and
/// after redo.
@MainActor
struct UndoPersistenceTests {
    private func values<T: Equatable>(
        _ t: TestLibrary, _ read: (ModelContext) -> T,
        _ action: () throws -> Void, before: T, after: T,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let undo = try #require(t.undo, sourceLocation: sourceLocation)
        func check(_ expected: T, _ step: String) {
            t.context.processPendingChanges()
            #expect(read(t.context) == expected, "main context, \(step)", sourceLocation: sourceLocation)
            #expect(read(ModelContext(t.container)) == expected, "second context, \(step)", sourceLocation: sourceLocation)
        }
        check(before, "start")
        try action()
        check(after, "after the action")
        undo.undo()
        check(before, "after undo")
        undo.redo()
        check(after, "after redo")
        undo.undo()
        check(before, "after a second undo")
    }

    @Test func renameCollection() throws {
        let t = try TestLibrary(undo: true)
        let collection = try t.library.createCollection(named: "Two")
        try values(t, { ($0.fetchCollectionNames()) }, {
            try t.library.renameCollection(collection, to: "Zwei")
        }, before: ["Two"], after: ["Zwei"])
    }

    @Test func editBook() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("Buddenbrooks", by: ["Thomas Mann"], year: 1901, isbn: "978-3-596-29431-2")
        try values(t, { $0.bookSummary() }, {
            var draft = BookDraft(book: book)
            draft.title = "Doktor Faustus"
            draft.yearText = "1947"
            draft.isbnText = ""
            draft.authors = [t.library.suggestedAuthor(for: "Erika Mann")]
            try t.library.updateBook(book, with: draft)
        }, before: ["Buddenbrooks|1901|978-3-596-29431-2|Thomas Mann"],
           after: ["Doktor Faustus|1947||Erika Mann"])
    }

    @Test func originalLanguage() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("Piercing")
        try values(t, { ctx in ((try? ctx.fetch(FetchDescriptor<Book>())) ?? []).map { $0.originalLanguage ?? "-" } }, {
            var draft = BookDraft(book: book)
            draft.language = "de"
            draft.originalLanguage = "ja"
            try t.library.updateBook(book, with: draft)
        }, before: ["-"], after: ["ja"])
    }

    @Test func noStatusRemovesWantToRead() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("A", status: .wantToRead)
        try values(t, { $0.readingSummary() }, {
            var draft = BookDraft(book: book)
            draft.status = nil
            try t.library.updateBook(book, with: draft)
        }, before: ["wantToRead|rating:0.0|"], after: [])
    }

    @Test func finishReading() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("A", status: .reading, started: date(2026, 10, 3))
        try values(t, { $0.readingSummary() }, {
            try t.library.finishReading(book, on: date(2026, 11, 1), rating: 4, notes: "Good")
        }, before: ["reading|rating:0.0|"], after: ["finished|rating:4.0|Good"])
    }

    @Test func abandonReading() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("A", status: .reading, started: date(2026, 10, 3))
        try values(t, { $0.readingSummary() }, {
            try t.library.abandonReading(book, on: date(2026, 11, 5), notes: "Boring")
        }, before: ["reading|rating:0.0|"], after: ["abandoned|rating:0.0|Boring"])
    }

    @Test func setCoverAndDeleteBookKeepTheirBytes() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("A")
        try values(t, { $0.coverSizes() }, {
            try t.library.setCover(Data(repeating: 1, count: 100), for: book)
        }, before: [0], after: [100])
        try t.library.setCover(Data(repeating: 1, count: 100), for: book)
        try values(t, { $0.coverSizes() }, {
            try t.library.deleteBook(book)
        }, before: [100], after: [])
    }
}

private extension ModelContext {
    func fetchCollectionNames() -> [String] {
        ((try? fetch(FetchDescriptor<Collection>())) ?? []).map(\.name).sorted()
    }

    @MainActor
    func bookSummary() -> [String] {
        ((try? fetch(FetchDescriptor<Book>())) ?? []).map {
            "\($0.title)|\($0.year ?? 0)|\($0.isbnText ?? "")|\($0.orderedAuthors.map(\.name).joined(separator: ","))"
        }.sorted()
    }

    func readingSummary() -> [String] {
        ((try? fetch(FetchDescriptor<Reading>())) ?? []).map {
            "\($0.statusRaw)|rating:\($0.stars ?? 0)|\($0.notes ?? "")"
        }.sorted()
    }

    func coverSizes() -> [Int] {
        ((try? fetch(FetchDescriptor<Book>())) ?? []).map { $0.coverImage?.count ?? 0 }.sorted()
    }
}
