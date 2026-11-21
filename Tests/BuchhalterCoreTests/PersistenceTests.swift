import Foundation
import SwiftData
import Testing
@testable import BuchhalterCore

@MainActor
struct PersistenceTests {
    @Test func everythingSurvivesReopeningTheStore() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: LibraryLocation.storeFileName)

        var collectionID = UUID()
        do {
            let container = try LibraryContainer.make(at: url)
            let library = Library(context: container.mainContext)
            let collection = try library.createCollection(named: "Read in 2026")
            collectionID = collection.id
            var draft = BookDraft()
            draft.title = "Der Zauberberg"
            draft.authors = [library.suggestedAuthor(for: "Thomas Mann")]
            draft.status = .read
            draft.startedAt = date(2026, 1, 1)
            draft.finishedAt = date(2026, 2, 1)
            draft.rating = 4
            draft.notes = "Great"
            draft.coverData = Data(repeating: 7, count: 50_000)
            draft.collectionIDs = [collection.id]
            try library.addBook(draft)
            try library.setViewMode(.grid, for: .collection(collection.id))
            try library.setSortLevels(SortLevels(levels: [SortLevel(field: .rating, direction: .descending)]), for: .collection(collection.id))
        }

        let container = try LibraryContainer.make(at: url)
        let library = Library(context: container.mainContext)
        let book = try #require(library.fetchBooks().first)
        #expect(book.title == "Der Zauberberg")
        #expect(book.orderedAuthors.first?.sortName == "Mann, Thomas")
        #expect(book.status == .finished)
        #expect(book.currentReading?.stars == 4)
        #expect(book.coverImage?.count == 50_000)
        #expect(book.collections?.first?.id == collectionID)
        #expect(library.preferences(for: .collection(collectionID)).viewMode == .grid)
        #expect(library.preferences(for: .collection(collectionID)).sortLevels.raw == "rating:desc")
    }
}
