import Foundation
import Testing
@testable import BuchhalterCore

@MainActor
struct DuplicateIndexTests {
    private func draft(_ title: String, authors: [String] = [], isbn: String = "") -> BookDraft {
        var draft = BookDraft()
        draft.title = title
        draft.authors = authors.map { AuthorDraft(name: $0, sortName: "") }
        draft.isbnText = isbn
        return draft
    }

    @Test func isbn10MatchesISBN13OfTheSameBook() throws {
        let t = try TestLibrary()
        try t.add("Buddenbrooks", isbn: "978-3-596-29431-2")
        let index = DuplicateIndex(books: t.library.fetchBooks())
        #expect(index.match(for: draft("Other", isbn: "3-596-29431-2")) != nil)
        #expect(index.match(for: draft("Other", isbn: "9783596294312")) != nil)
        #expect(index.match(for: draft("Other", isbn: "0-8044-2957-X")) == nil)
    }

    @Test func titlePlusCommonAuthor() throws {
        let t = try TestLibrary()
        try t.add("Der Zauberberg", by: ["Thomas Mann"], year: 1924)
        let index = DuplicateIndex(books: t.library.fetchBooks())
        let hit = index.match(for: draft("der zauberberg", authors: ["thomas MANN"]))
        #expect(hit?.label == "Der Zauberberg (1924)")
        #expect(index.match(for: draft("Der Zauberberg", authors: ["Heinrich Mann"])) == nil)
        #expect(index.match(for: draft("Der Zauberberg")) == nil)
        #expect(index.match(for: draft("Other", authors: ["Thomas Mann"])) == nil)
    }

    @Test func editExcludesItself() throws {
        let t = try TestLibrary()
        let book = try t.add("Der Zauberberg", by: ["Thomas Mann"], isbn: "978-3-596-29431-2")
        let index = DuplicateIndex(books: t.library.fetchBooks(), excluding: book.id)
        #expect(index.match(for: BookDraft(book: book)) == nil)
    }

    @Test func labelWithoutYear() {
        #expect(DuplicateIndex.label(title: "Stoner", year: nil) == "Stoner")
        #expect(DuplicateIndex.label(title: "Der Zauberberg", year: 1924) == "Der Zauberberg (1924)")
    }
}

@MainActor
struct DuplicateIndexISBNTests {
    @Test func matchesAnISBN13() throws {
        let t = try TestLibrary()
        let book = try t.add("Buddenbrooks", by: ["Thomas Mann"], year: 1901, isbn: "978-3-596-29431-2")
        try t.add("Stoner", isbn: "")
        let index = DuplicateIndex(books: t.library.fetchBooks())
        let hit = index.match(isbn13: "9783596294312")
        #expect(hit?.bookID == book.id)
        #expect(hit?.label == "Buddenbrooks (1901)")
        #expect(index.match(isbn13: "9780306406157") == nil)
        #expect(index.match(isbn13: "") == nil)
    }
}
