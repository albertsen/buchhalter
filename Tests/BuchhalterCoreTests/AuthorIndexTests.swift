import Foundation
import Testing
@testable import BuchhalterCore

@MainActor
struct AuthorIndexTests {
    private func entry(_ name: String, sortedAs sortName: String) -> AuthorEntry {
        AuthorEntry(id: UUID(), name: name, sortName: sortName, bookCount: 1)
    }

    @Test func lettersFollowTheFoldedSortName() {
        #expect(AuthorIndex.letter(for: "Mann, Thomas") == "M")
        #expect(AuthorIndex.letter(for: "Goethe, Johann Wolfgang von") == "G")
        #expect(AuthorIndex.letter(for: "Ärger, Anna") == "A")
        #expect(AuthorIndex.letter(for: "öztürk, Elif") == "O")
        #expect(AuthorIndex.letter(for: "1984 Kollektiv") == "#")
        #expect(AuthorIndex.letter(for: "Толстой, Лев") == "#")
        #expect(AuthorIndex.letter(for: "") == "#")
    }

    @Test func sectionsAreOrderedWithTheOtherLetterLast() throws {
        let t = try TestLibrary()
        for (title, author) in [
            ("Buddenbrooks", "Thomas Mann"), ("Faust", "Johann Wolfgang von Goethe"),
            ("Kollektiv", "1984 Kollektiv"), ("Unruh", "Anna Ärger"), ("Effi Briest", "Theodor Fontane"),
            ("Die Blechtrommel", "Günter Grass"),
        ] {
            try t.add(title, by: [author])
        }
        // The guess would be "Kollektiv, 1984".
        let collective = try #require(t.library.fetchBooks().flatMap(\.orderedAuthors).first { $0.name == "1984 Kollektiv" })
        try t.library.setSortName("1984 Kollektiv", for: collective)
        let entries = AuthorIndex.authors(in: t.library.fetchBooks())
        #expect(entries.map(\.name) == [
            "Anna Ärger", "Theodor Fontane", "Johann Wolfgang von Goethe", "Günter Grass", "Thomas Mann", "1984 Kollektiv",
        ])
        let sections = AuthorIndex.sections(entries)
        #expect(sections.map(\.letter) == ["A", "F", "G", "M", "#"])
        #expect(sections.first { $0.letter == "G" }?.authors.map(\.name) == ["Johann Wolfgang von Goethe", "Günter Grass"])
    }

    @Test func anEmptySortNameFallsBackToTheName() {
        let entries = [entry("Homer", sortedAs: ""), entry("Hesse", sortedAs: "Hesse, Hermann")]
        #expect(entries.sorted(by: AuthorIndex.areInOrder).map(\.name) == ["Hesse", "Homer"])
        #expect(AuthorIndex.sections(entries.sorted(by: AuthorIndex.areInOrder)).map(\.letter) == ["H"])
    }

    @Test func onlyAuthorsWithBooksAreListedAndCounted() throws {
        let t = try TestLibrary()
        let only = try t.add("Stoner", by: ["John Williams"])
        try t.add("Buddenbrooks", by: ["Thomas Mann"])
        try t.add("Der Zauberberg", by: ["Thomas Mann"])
        var books = t.library.fetchBooks()
        #expect(AuthorIndex.authors(in: books).map(\.bookCount) == [2, 1])
        #expect(LibraryLists.counts(books: books, collections: [])[.authors] == 2)

        try t.library.deleteBook(only)
        books = t.library.fetchBooks()
        #expect(AuthorIndex.authors(in: books).map(\.name) == ["Thomas Mann"])
        #expect(LibraryLists.counts(books: books, collections: [])[.authors] == 1)
    }

    @Test func aBookWithTwoAuthorsCountsForBoth() throws {
        let t = try TestLibrary()
        let book = try t.add("Gemeinsam", by: ["Thomas Mann", "Lisa Seidl"], year: 1959)
        let books = t.library.fetchBooks()
        let entries = AuthorIndex.authors(in: books)
        #expect(entries.map(\.name) == ["Thomas Mann", "Lisa Seidl"])
        #expect(entries.allSatisfy { $0.bookCount == 1 })
        for entry in entries {
            #expect(AuthorIndex.books(by: entry.id, in: books).map(\.title) == ["Gemeinsam"])
        }
        let mann = try #require(entries.first)
        #expect(AuthorIndex.coauthors(of: book, excluding: mann.id) == ["Lisa Seidl"])
    }

    @Test func searchMatchesNameAndSortNameIgnoringAccents() {
        let entries = [entry("Heinrich Böll", sortedAs: "Böll, Heinrich"), entry("Mo Yan", sortedAs: "Mo Yan"),
                       entry("Homer", sortedAs: "Homeros")]
        #expect(AuthorIndex.filter(entries, query: "boll").map(\.name) == ["Heinrich Böll"])
        #expect(AuthorIndex.filter(entries, query: "homeros").map(\.name) == ["Homer"])
        #expect(AuthorIndex.filter(entries, query: "heinrich BÖLL").map(\.name) == ["Heinrich Böll"])
        #expect(AuthorIndex.filter(entries, query: "rilke").isEmpty)
        #expect(AuthorIndex.filter(entries, query: "  ").count == 3)
    }

    @Test func anAuthorsBooksAreOldestFirstWithTiesByTitleAndNoYearLast() throws {
        let t = try TestLibrary()
        try t.add("Doktor Faustus", by: ["Thomas Mann"], year: 1947)
        try t.add("Ohne Jahr", by: ["Thomas Mann"])
        try t.add("Tristan", by: ["Thomas Mann"], year: 1903)
        try t.add("Buddenbrooks", by: ["Thomas Mann"], year: 1901)
        try t.add("Der Zauberberg", by: ["Thomas Mann"], year: 1924)
        try t.add("Tonio Kröger", by: ["Thomas Mann"], year: 1903)
        try t.add("Stoner", by: ["John Williams"], year: 1965)
        let books = t.library.fetchBooks()
        let mann = try #require(AuthorIndex.authors(in: books).first { $0.name == "Thomas Mann" })
        #expect(AuthorIndex.books(by: mann.id, in: books).map(\.title) == [
            "Buddenbrooks", "Tonio Kröger", "Tristan", "Der Zauberberg", "Doktor Faustus", "Ohne Jahr",
        ])
    }

    @Test func aNewSortNameMovesTheAuthor() throws {
        let t = try TestLibrary(undo: true)
        try t.add("Hundert Jahre Einsamkeit", by: ["Gabriel García Márquez"])
        try t.add("Buddenbrooks", by: ["Thomas Mann"])
        let gabo = try #require(t.library.fetchBooks().flatMap(\.orderedAuthors).first { $0.name.hasPrefix("Gabriel") })
        try t.library.setSortName("Márquez, Gabriel García", for: gabo)
        var sections = AuthorIndex.sections(AuthorIndex.authors(in: t.library.fetchBooks()))
        #expect(sections.map(\.letter) == ["M"])
        try t.library.setSortName("García Márquez, Gabriel", for: gabo)
        #expect(t.undo?.undoActionName == "Edit Sorted As")
        sections = AuthorIndex.sections(AuthorIndex.authors(in: t.library.fetchBooks()))
        #expect(sections.map(\.letter) == ["G", "M"])
    }
}
