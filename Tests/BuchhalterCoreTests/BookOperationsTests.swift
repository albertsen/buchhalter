import Foundation
import SwiftData
import Testing
@testable import BuchhalterCore

@MainActor
struct BookOperationsTests {
    @Test func addWithEachStatusCreatesTheRightReading() throws {
        let t = try TestLibrary()
        let want = try t.add("A", status: .wantToRead)
        let reading = try t.add("B", status: .reading, started: date(2026, 10, 3))
        let read = try t.add("C", status: .read, started: date(2026, 1, 1), finished: date(2026, 2, 1), rating: 4, notes: " Nice ")
        #expect(want.status == .wantToRead && want.readings?.count == 1)
        #expect(reading.status == .reading)
        #expect(reading.currentReading?.startedAt == date(2026, 10, 3))
        #expect(read.status == .finished)
        #expect(read.currentReading?.endedAt == date(2026, 2, 1))
        #expect(read.currentReading?.stars == 4)
        #expect(read.currentReading?.notes == "Nice")
        #expect(want.originRaw == "manual")
    }

    @Test func addWithoutStatusCreatesNoReading() throws {
        let t = try TestLibrary()
        let book = try t.add("Owned", status: nil)
        #expect(book.readings?.isEmpty == true)
        #expect(book.status == nil)
    }

    @Test func noStatusRemovesTheCurrentReadingOnly() throws {
        let t = try TestLibrary()
        let reading = try t.add("A", status: .reading, started: date(2026, 10, 3))
        let read = try t.add("B", status: .read, finished: date(2026, 2, 1), rating: 5)
        for book in [reading, read] {
            var draft = BookDraft(book: book)
            draft.status = nil
            try t.library.updateBook(book, with: draft)
            #expect(book.readings?.isEmpty == true)
            #expect(book.status == nil)
        }
        // A reread: removing the new reading leaves the earlier finished one.
        let reread = try t.add("C", status: .read, finished: date(2025, 2, 1))
        try t.library.readAgain(reread)
        var draft = BookDraft(book: reread)
        draft.status = nil
        try t.library.updateBook(reread, with: draft)
        #expect(reread.readings?.count == 1)
        #expect(reread.status == .finished)
    }

    @Test func noStatusKeepsAnAbandonedReading() throws {
        let t = try TestLibrary()
        let book = try t.add("A", status: .reading, started: date(2026, 10, 3))
        try t.library.abandonReading(book, on: date(2026, 11, 1), notes: nil)
        let draft = BookDraft(book: book)
        #expect(draft.status == nil)
        try t.library.updateBook(book, with: draft)
        #expect(book.status == .abandoned)
    }

    @Test func originalLanguageIsStoredAndDroppedWhenSame() throws {
        let t = try TestLibrary()
        var draft = BookDraft()
        draft.title = "Piercing"
        draft.language = "de"
        draft.originalLanguage = "ja"
        let book = try t.library.addBook(draft)
        #expect(book.originalLanguage == "ja")
        #expect(BookDraft(book: book).originalLanguage == "ja")
        var same = BookDraft(book: book)
        same.originalLanguage = "de"
        try t.library.updateBook(book, with: same)
        #expect(book.originalLanguage == nil)
    }

    @Test func readingStatusDefaultsStartToToday() throws {
        let t = try TestLibrary()
        let book = try t.add("B", status: .reading)
        let start = try #require(book.currentReading?.startedAt)
        #expect(Calendar.current.isDateInToday(start))
    }

    @Test func authorsAreReusedAndOrderIsKept() throws {
        let t = try TestLibrary()
        let a = try t.add("A", by: ["Thomas Mann", "Erika Mann"])
        let b = try t.add("B", by: ["thomas  mann"])
        #expect(try t.context.fetchCount(FetchDescriptor<Author>()) == 2)
        #expect(a.orderedAuthors.map(\.name) == ["Thomas Mann", "Erika Mann"])
        #expect(b.orderedAuthors.first === a.orderedAuthors.first)
    }

    @Test func sortNameChangeAffectsAllBooks() throws {
        let t = try TestLibrary()
        let a = try t.add("A", by: ["Thomas Mann"])
        let b = try t.add("B", by: ["Thomas Mann"])
        let author = try #require(a.orderedAuthors.first)
        try t.library.setSortName("Zzz, Thomas", for: author)
        #expect(b.orderedAuthors.first?.sortName == "Zzz, Thomas")
        try t.library.setSortName("  ", for: author)
        #expect(author.sortName == "Mann, Thomas")
    }

    @Test func editedSortNameInDraftIsApplied() throws {
        let t = try TestLibrary()
        var draft = BookDraft()
        draft.title = "Mo"
        draft.authors = [AuthorDraft(name: "Mo Yan", sortName: "Mo Yan")]
        let book = try t.library.addBook(draft)
        #expect(book.orderedAuthors.first?.sortName == "Mo Yan")
        #expect(t.library.suggestedAuthor(for: "mo yan").isExisting)
    }

    @Test func updateRebuildsAuthorships() throws {
        let t = try TestLibrary()
        let book = try t.add("A", by: ["Thomas Mann", "Erika Mann"])
        var draft = BookDraft(book: book)
        draft.title = "A2"
        draft.authors = [draft.authors[1], t.library.suggestedAuthor(for: "Klaus Mann")]
        try t.library.updateBook(book, with: draft)
        #expect(book.title == "A2")
        #expect(book.orderedAuthors.map(\.name) == ["Erika Mann", "Klaus Mann"])
        #expect(try t.context.fetchCount(FetchDescriptor<Authorship>()) == 2)
        // Thomas Mann stays as an author without books.
        #expect(try t.context.fetchCount(FetchDescriptor<Author>()) == 3)
    }

    @Test func updateTrimsAndClearsOptionalFields() throws {
        let t = try TestLibrary()
        let book = try t.add("A", year: 1900, pages: 10, isbn: "978-3-596-29431-2")
        var draft = BookDraft(book: book)
        draft.yearText = ""
        draft.pagesText = ""
        draft.isbnText = "  "
        draft.subtitle = "  "
        try t.library.updateBook(book, with: draft)
        #expect(book.year == nil && book.pageCount == nil)
        #expect(book.isbnText == nil && book.isbn13 == nil && book.subtitle == nil)
    }

    @Test func addRejectsInvalidDraft() throws {
        let t = try TestLibrary()
        #expect(throws: LibraryError.self) { try t.library.addBook(BookDraft()) }
        var draft = BookDraft()
        draft.title = "x"
        draft.isbnText = "978-3-10-048431-7"
        #expect(throws: LibraryError.self) { try t.library.addBook(draft) }
        #expect(t.library.fetchBooks().isEmpty)
    }

    @Test func updateKeepsOrRewritesReadingsByStatus() throws {
        let t = try TestLibrary()
        let book = try t.add("A", status: .wantToRead)
        var draft = BookDraft(book: book)
        draft.status = .reading
        draft.startedAt = date(2026, 3, 1)
        try t.library.updateBook(book, with: draft)
        #expect(book.readings?.count == 1)
        #expect(book.status == .reading)
        draft.status = .read
        draft.finishedAt = date(2026, 4, 1)
        try t.library.updateBook(book, with: draft)
        #expect(book.readings?.count == 1)
        #expect(book.status == .finished)
        // Finished to Reading starts a new reading.
        draft = BookDraft(book: book)
        draft.status = .reading
        draft.startedAt = date(2026, 5, 1)
        try t.library.updateBook(book, with: draft)
        #expect(book.readings?.count == 2)
        #expect(book.status == .reading)
    }

    @Test func deleteCascadesReadingsAndKeepsAuthorsAndCollections() throws {
        let t = try TestLibrary()
        let collection = try t.library.createCollection(named: "Owned")
        let book = try t.add("A", by: ["Thomas Mann"], collections: [collection.id])
        let other = try t.add("B", collections: [collection.id])
        try t.library.deleteBook(book)
        #expect(try t.context.fetchCount(FetchDescriptor<Book>()) == 1)
        #expect(try t.context.fetchCount(FetchDescriptor<Reading>()) == 1)
        #expect(try t.context.fetchCount(FetchDescriptor<Authorship>()) == 0)
        #expect(try t.context.fetchCount(FetchDescriptor<Author>()) == 1)
        #expect(collection.books?.count == 1)
        #expect(collection.books?.first === other)
    }

    @Test func setAndRemoveCover() throws {
        let t = try TestLibrary()
        let book = try t.add("A")
        try t.library.setCover(Data([9, 9]), for: book)
        #expect(book.coverImage == Data([9, 9]))
        try t.library.setCover(nil, for: book)
        #expect(book.coverImage == nil)
    }
    // MARK: Lookup

    @Test func lookupAuthorsReuseAnExistingAuthorWithItsSortName() throws {
        let t = try TestLibrary()
        let book = try t.add("A", by: ["Thomas Mann"])
        let author = try #require(book.orderedAuthors.first)
        try t.library.setSortName("Mann, Thomas (Autor)", for: author)
        let drafts = t.library.lookupAuthors([
            LookupAuthor(name: "thomas mann", sortName: "Mann, Thomas"),
            LookupAuthor(name: "Thomas Mann"),
        ])
        #expect(drafts.count == 1)
        #expect(drafts.first?.name == "Thomas Mann")
        #expect(drafts.first?.sortName == "Mann, Thomas (Autor)")
        #expect(drafts.first?.isExisting == true)
    }

    @Test func lookupAuthorsGiveNewAuthorsTheHeadingSortNameOrAGuess() throws {
        let t = try TestLibrary()
        let drafts = t.library.lookupAuthors([
            LookupAuthor(name: "Ryū Murakami", sortName: "Murakami, Ryū"),
            LookupAuthor(name: "John Williams"),
        ])
        #expect(drafts.map(\.name) == ["Ryū Murakami", "John Williams"])
        #expect(drafts.map(\.sortName) == ["Murakami, Ryū", "Williams, John"])
        #expect(drafts.allSatisfy { !$0.isExisting })
        // Nothing was inserted.
        #expect(try t.context.fetchCount(FetchDescriptor<Author>()) == 0)
    }

    @Test func addWithLookupOriginStoresItAndUndoRedoRestoresIt() throws {
        let t = try TestLibrary(undo: true)
        var draft = BookDraft()
        draft.title = "Piercing"
        let book = try t.library.addBook(draft, origin: .lookup, originNote: "dnb:991442512")
        #expect(book.originRaw == "lookup")
        #expect(book.originNote == "dnb:991442512")

        t.undo?.undo()
        #expect(try t.context.fetchCount(FetchDescriptor<Book>()) == 0)
        t.undo?.redo()
        let restored = try #require(try t.context.fetch(FetchDescriptor<Book>()).first)
        #expect(restored.originRaw == "lookup")
        #expect(restored.originNote == "dnb:991442512")
    }
}

@MainActor
struct DateAddedTests {
    @Test func dateAddedIsSetEditedAndUndone() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("A")
        #expect(abs(book.addedAt.timeIntervalSinceNow) < 60)
        var draft = BookDraft(book: book)
        #expect(draft.addedAt == book.addedAt)
        let before = book.addedAt
        draft.addedAt = date(2019, 5, 1)
        try t.library.updateBook(book, with: draft)
        #expect(book.addedAt == date(2019, 5, 1))
        t.undo?.undo()
        #expect(book.addedAt == before)
    }

    @Test func addingWithAnEarlierDay() throws {
        let t = try TestLibrary()
        var draft = BookDraft()
        draft.title = "Old shelf book"
        draft.addedAt = date(2020, 1, 15)
        let book = try t.library.addBook(draft)
        #expect(book.addedAt == date(2020, 1, 15))
        #expect(BookFormatting(locale: Locale(identifier: "en"), timeZone: .current).added(book).hasPrefix("Added "))
    }

    // MARK: Inline details

    @Test func updateDetailsChangesFieldsAndLeavesReadingsAlone() throws {
        let t = try TestLibrary()
        let book = try t.add("Old", by: ["Thomas Mann"], status: .read, finished: date(2026, 2, 1), rating: 4)
        // A finished reading without a date, as the LibraryThing import made them.
        book.currentReading?.endedAt = nil
        book.coverImage = Data([1, 2, 3])
        try t.library.updateDetails(of: book) { draft in
            draft.title = "New"
            draft.yearText = "1901"
            draft.authors = [AuthorDraft(name: "Heinrich Mann", sortName: "Mann, Heinrich")]
        }
        #expect(book.title == "New")
        #expect(book.year == 1901)
        #expect(book.orderedAuthors.map(\.name) == ["Heinrich Mann"])
        #expect(book.currentReading?.endedAt == nil)
        #expect(book.currentReading?.stars == 4)
        #expect(book.readings?.count == 1)
        #expect(book.coverImage == Data([1, 2, 3]))
    }

    @Test func editBookKeepsAnUndatedFinishedReadingUndated() throws {
        let t = try TestLibrary()
        let book = try t.add("A", status: .read, finished: date(2026, 2, 1), rating: 4)
        book.currentReading?.endedAt = nil
        var draft = BookDraft(book: book)
        #expect(draft.finishedAt == nil)
        draft.title = "B"
        try t.library.updateBook(book, with: draft)
        #expect(book.title == "B")
        #expect(book.currentReading?.endedAt == nil)
        #expect(book.currentReading?.stars == 4)
        #expect(book.readings?.count == 1)
    }

    @Test func updateDetailsRejectsInvalidValues() throws {
        let t = try TestLibrary()
        let book = try t.add("A", year: 2000)
        #expect(throws: LibraryError.self) { try t.library.updateDetails(of: book) { $0.title = " " } }
        #expect(throws: LibraryError.self) { try t.library.updateDetails(of: book) { $0.yearText = "19x" } }
        #expect(throws: LibraryError.self) { try t.library.updateDetails(of: book) { $0.pagesText = "0" } }
        #expect(throws: LibraryError.self) { try t.library.updateDetails(of: book) { $0.isbnText = "978-3" } }
        #expect(book.title == "A" && book.year == 2000)
    }

    @Test func updateDetailsIsOneUndoStep() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("A")
        try t.library.updateDetails(of: book) { $0.title = "B" }
        try #require(t.undo).undo()
        #expect(book.title == "A")
    }
}
