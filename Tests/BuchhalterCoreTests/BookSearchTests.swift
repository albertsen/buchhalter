import Testing
@testable import BuchhalterCore

struct BookSearchTests {
    private let key = SearchKey(
        title: "Der Zauberberg", subtitle: "Roman", authors: ["Heinrich Böll", "Thomas Mann"],
        publisher: "S. Fischer", isbnText: "978-3-596-29431-2", isbn13: "9783596294312",
        notes: ["Slow start, then hard to put down"]
    )

    @Test func foldsCaseAndAccents() {
        #expect(BookSearch.matches(key, query: "boll"))
        #expect(BookSearch.matches(key, query: "BÖLL"))
        #expect(!BookSearch.matches(key, query: "xyz"))
    }

    @Test func matchesEveryField() {
        for query in ["zauber", "roman", "thomas", "fischer", "hard to put", "978-3-596", "9783596", "978 3"] {
            #expect(BookSearch.matches(key, query: query), "\(query)")
        }
    }

    @Test func allTokensMustMatch() {
        #expect(BookSearch.matches(key, query: "mann zauber"))
        #expect(!BookSearch.matches(key, query: "mann hesse"))
        #expect(BookSearch.matches(key, query: "   "))
    }

    @MainActor
    @Test func filtersBooks() throws {
        let t = try TestLibrary()
        try t.add("Ansichten eines Clowns", by: ["Heinrich Böll"])
        try t.add("Stoner", by: ["John Williams"])
        #expect(BookSearch.filter(t.library.fetchBooks(), query: "boll").map(\.title) == ["Ansichten eines Clowns"])
    }
}
