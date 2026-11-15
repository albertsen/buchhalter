import Foundation
import Testing
@testable import BuchhalterCore

struct BookDraftTests {
    @Test func emptyTitleIsAnIssue() {
        var draft = BookDraft()
        #expect(draft.issues == [.emptyTitle])
        draft.title = "  "
        #expect(draft.issues.contains(.emptyTitle))
        draft.title = "Stoner"
        #expect(draft.canSave)
    }

    @Test func isbnRules() {
        var draft = BookDraft()
        draft.title = "x"
        draft.isbnText = ""
        #expect(draft.canSave)
        draft.isbnText = "978-3-10-048431-7"
        #expect(draft.issues == [.invalidISBN])
        draft.isbnText = "978-3"
        #expect(draft.issues == [.invalidISBN])
        draft.isbnText = "978-3-596-29431-2"
        #expect(draft.canSave)
    }

    @Test func yearAndPagesValidation() {
        var draft = BookDraft()
        draft.title = "x"
        draft.yearText = "19x4"
        draft.pagesText = "-3"
        #expect(draft.issues == [.invalidYear, .invalidPages])
        draft.yearText = "1924"
        draft.pagesText = "1008"
        #expect(draft.canSave)
        #expect(draft.year == 1924)
        #expect(draft.pages == 1008)
        draft.yearText = "0"
        #expect(draft.issues == [.invalidYear])
    }

    @Test func finishBeforeStartIsAnIssueOnlyForRead() {
        var draft = BookDraft()
        draft.title = "x"
        draft.startedAt = date(2026, 5, 1)
        draft.finishedAt = date(2026, 4, 1)
        draft.status = .reading
        #expect(draft.canSave)
        draft.status = .read
        #expect(draft.issues == [.finishBeforeStart])
    }

    @MainActor
    @Test func roundTripFromBook() throws {
        let t = try TestLibrary()
        var draft = BookDraft()
        draft.title = "Der Zauberberg"
        draft.subtitle = "Roman"
        draft.authors = [t.library.suggestedAuthor(for: "Thomas Mann")]
        draft.yearText = "1924"
        draft.pagesText = "1008"
        draft.language = "de"
        draft.publisher = "S. Fischer"
        draft.isbnText = "978-3-596-29431-2"
        draft.status = .read
        draft.startedAt = date(2026, 1, 1)
        draft.finishedAt = date(2026, 2, 1)
        draft.rating = 4
        draft.notes = "Great"
        draft.coverData = Data([1, 2, 3])
        let book = try t.library.addBook(draft)
        let back = BookDraft(book: book)
        #expect(back.title == "Der Zauberberg")
        #expect(back.subtitle == "Roman")
        #expect(back.authors.map(\.name) == ["Thomas Mann"])
        #expect(back.authors.first?.sortName == "Mann, Thomas")
        #expect(back.year == 1924 && back.pages == 1008)
        #expect(back.language == "de")
        #expect(back.isbnText == "978-3-596-29431-2")
        #expect(back.status == .read)
        #expect(back.rating == 4 && back.notes == "Great")
        #expect(back.startedAt == date(2026, 1, 1) && back.finishedAt == date(2026, 2, 1))
        #expect(back.coverData == Data([1, 2, 3]))
        #expect(back.canSave)
    }

    @MainActor
    @Test func abandonedAndEmptyBooksHaveNoDraftStatus() throws {
        let t = try TestLibrary()
        let abandoned = try t.add("A", status: .reading)
        try t.library.abandonReading(abandoned, on: nil, notes: nil)
        #expect(BookDraft(book: abandoned).status == nil)
        let plain = try t.add("B")
        try t.library.deleteReading(try #require(plain.currentReading))
        #expect(BookDraft(book: plain).status == nil)
    }
}
