import Foundation
import SwiftData
import Testing
@testable import BuchhalterCore

/// A change that arrives from another device never passes through
/// `Library.change`, so it is not on the undo stack, and undoing an own action
/// writes only the fields that action changed. A second `ModelContext` on the
/// same container stands in for the other device.
@MainActor
struct UndoSyncTests {
    @Test func undoRevertsTheOwnFieldAndLeavesWhatAnotherDeviceChanged() throws {
        let t = try TestLibrary(undo: true)
        let undo = try #require(t.undo)
        let book = try t.add("Buddenbrooks", by: ["Thomas Mann"])
        let id = book.id
        try t.library.updateDetails(of: book) { $0.title = "Die Buddenbrooks" }

        // The other device changes the publisher of the same book and saves.
        let other = ModelContext(t.container)
        let remote = try #require(try other.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first)
        remote.publisher = "Fischer"
        try other.save()

        undo.undo()

        let fresh = ModelContext(t.container)
        let stored = try #require(try fresh.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first)
        #expect(stored.title == "Buddenbrooks")
        #expect(stored.publisher == "Fischer")

        undo.redo()
        let again = ModelContext(t.container)
        let redone = try #require(try again.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first)
        #expect(redone.title == "Die Buddenbrooks")
        #expect(redone.publisher == "Fischer")
    }

    @Test func aChangeFromAnotherDeviceIsNotOnTheUndoStack() throws {
        let t = try TestLibrary(undo: true)
        let undo = try #require(t.undo)
        let book = try t.add("Buddenbrooks")
        let id = book.id
        // Adding the book is an undo step of its own; start from an empty stack.
        undo.removeAllActions()
        try t.library.updateDetails(of: book) { $0.title = "Die Buddenbrooks" }
        undo.undo()
        #expect(!undo.canUndo)

        let other = ModelContext(t.container)
        let remote = try #require(try other.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first)
        remote.publisher = "Fischer"
        try other.save()

        #expect(!undo.canUndo)
        undo.undo()
        let fresh = ModelContext(t.container)
        #expect(try fresh.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first?.publisher == "Fischer")
    }

    @Test func undoingAnEditOfABookDeletedElsewhereNeitherCrashesNorBringsItBack() throws {
        let t = try TestLibrary(undo: true)
        let undo = try #require(t.undo)
        let book = try t.add("Buddenbrooks", by: ["Thomas Mann"])
        let id = book.id
        try t.library.updateDetails(of: book) { $0.title = "Die Buddenbrooks" }

        let other = ModelContext(t.container)
        let remote = try #require(try other.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first)
        other.delete(remote)
        try other.save()

        undo.undo()
        undo.redo()

        #expect(try ModelContext(t.container).fetchCount(FetchDescriptor<Book>()) == 0)
    }

    @Test func undoingADeleteBringsTheBookBackAndItSyncsAgainAsANewInsert() throws {
        let t = try TestLibrary(undo: true)
        let undo = try #require(t.undo)
        let book = try t.add("Buddenbrooks", by: ["Thomas Mann"], rating: nil)
        try t.library.deleteBook(book)
        #expect(try ModelContext(t.container).fetchCount(FetchDescriptor<Book>()) == 0)
        undo.undo()
        #expect(try ModelContext(t.container).fetchCount(FetchDescriptor<Book>()) == 1)
    }
}
