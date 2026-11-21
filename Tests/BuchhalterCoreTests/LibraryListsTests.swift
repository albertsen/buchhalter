import Foundation
import Testing
@testable import BuchhalterCore

@MainActor
struct LibraryListsTests {
    @Test func membershipAndCounts() throws {
        let t = try TestLibrary()
        let owned = try t.library.createCollection(named: "Owned")
        let a = try t.add("A", status: .wantToRead, collections: [owned.id])
        let b = try t.add("B", status: .reading)
        let c = try t.add("C", status: .read)
        let d = try t.add("D", status: .reading)
        try t.library.abandonReading(d, on: nil, notes: nil)
        let e = try t.add("E", status: .read)
        try t.library.readAgain(e)
        let books = t.library.fetchBooks()

        func titles(_ list: LibraryListID) -> Set<String> {
            Set(LibraryLists.books(in: list, from: books).map(\.title))
        }
        #expect(titles(.wantToRead) == ["A"])
        #expect(titles(.reading) == ["B", "E"])
        #expect(titles(.read) == ["C"])
        #expect(titles(.all) == ["A", "B", "C", "D", "E"])
        #expect(titles(.collection(owned.id)) == ["A"])
        _ = (a, b, c)

        let counts = LibraryLists.counts(books: books, collections: t.library.fetchCollections())
        #expect(counts[.reading] == 2)
        #expect(counts[.wantToRead] == 1)
        #expect(counts[.read] == 1)
        #expect(counts[.all] == 5)
        #expect(counts[.collection(owned.id)] == 1)
        #expect(counts[.authors] == 0)
        #expect(LibraryLists.books(in: .authors, from: books).isEmpty)
    }

    @Test func bookWithoutReadingsIsOnlyInAllBooksAndCollections() throws {
        let t = try TestLibrary()
        let owned = try t.library.createCollection(named: "Owned")
        let book = try t.add("A", status: .wantToRead, collections: [owned.id])
        let reading = try #require(book.currentReading)
        try t.library.deleteReading(reading)
        let books = t.library.fetchBooks()
        #expect(book.status == nil)
        #expect(LibraryLists.books(in: .all, from: books).count == 1)
        #expect(LibraryLists.books(in: .wantToRead, from: books).isEmpty)
        #expect(LibraryLists.books(in: .collection(owned.id), from: books).count == 1)
    }

    @Test func listIDRoundTrips() throws {
        let id = UUID()
        for list in [LibraryListID.reading, .wantToRead, .read, .all, .authors, .collection(id)] {
            #expect(LibraryListID(rawValue: list.rawValue) == list)
            let data = try JSONEncoder().encode(list)
            #expect(try JSONDecoder().decode(LibraryListID.self, from: data) == list)
        }
        #expect(LibraryListID(rawValue: "bogus") == nil)
        #expect(LibraryListID.collection(id).settingsKey.isEmpty)
        #expect(LibraryListID.all.settingsKey == "all")
        #expect(!LibraryListID.builtIn.contains(.authors))
    }
}
