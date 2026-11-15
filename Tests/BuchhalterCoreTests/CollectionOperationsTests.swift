import Foundation
import SwiftData
import Testing
@testable import BuchhalterCore

@MainActor
struct CollectionOperationsTests {
    @Test func namesAreValidated() throws {
        let t = try TestLibrary()
        try t.library.createCollection(named: "Read in 2026")
        #expect(t.library.validateCollectionName("  ") != nil)
        #expect(throws: LibraryError.self) { try t.library.createCollection(named: "") }
        #expect(throws: LibraryError.self) { try t.library.createCollection(named: "read in 2026") }
        #expect(throws: LibraryError.self) { try t.library.createCollection(named: "Réad  in 2026") }
        #expect(t.library.fetchCollections().count == 1)
        #expect(t.library.validateCollectionName("Owned") == nil)
    }

    @Test func renameKeepsItsOwnNameAvailable() throws {
        let t = try TestLibrary()
        let a = try t.library.createCollection(named: "A")
        try t.library.createCollection(named: "B")
        try t.library.renameCollection(a, to: "a")
        #expect(a.name == "a")
        #expect(throws: LibraryError.self) { try t.library.renameCollection(a, to: "B") }
    }

    @Test func createAppendsAndMoveRenumbers() throws {
        let t = try TestLibrary()
        let a = try t.library.createCollection(named: "A")
        let b = try t.library.createCollection(named: "B")
        let c = try t.library.createCollection(named: "C")
        #expect([a, b, c].map(\.sortIndex) == [0, 1, 2])
        try t.library.moveCollections(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(t.library.fetchCollections().map(\.name) == ["C", "A", "B"])
        #expect(t.library.fetchCollections().map(\.sortIndex) == [0, 1, 2])
        try t.library.moveCollections(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(t.library.fetchCollections().map(\.name) == ["A", "B", "C"])
    }

    @Test func deleteKeepsBooksAndRemovesSettings() throws {
        let t = try TestLibrary()
        let collection = try t.library.createCollection(named: "A")
        let book = try t.add("Book", collections: [collection.id])
        try t.library.setViewMode(.grid, for: .collection(collection.id))
        #expect(try t.context.fetchCount(FetchDescriptor<ListSettings>()) == 1)
        try t.library.deleteCollection(collection)
        #expect(try t.context.fetchCount(FetchDescriptor<Collection>()) == 0)
        #expect(try t.context.fetchCount(FetchDescriptor<ListSettings>()) == 0)
        #expect(t.library.fetchBooks().count == 1)
        #expect(book.collections?.isEmpty == true)
    }

    @Test func addRemoveToggle() throws {
        let t = try TestLibrary()
        let collection = try t.library.createCollection(named: "A")
        let book = try t.add("Book")
        try t.library.add(book, to: collection)
        try t.library.add(book, to: collection)
        #expect(book.collections?.count == 1)
        try t.library.toggle(book, in: collection)
        #expect(book.collections?.isEmpty == true)
        try t.library.toggle(book, in: collection)
        #expect(collection.books?.count == 1)
        try t.library.remove(book, from: collection)
        #expect(collection.books?.isEmpty == true)
    }

    @Test func createAndAddInOneStep() throws {
        let t = try TestLibrary()
        let book = try t.add("Book")
        let collection = try t.library.createCollection(named: "New", adding: book)
        #expect(book.collections?.first === collection)
        #expect(throws: LibraryError.self) { try t.library.createCollection(named: "new", adding: book) }
    }
}
