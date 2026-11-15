import Foundation
import SwiftData
import Testing
@testable import BuchhalterCore

/// Runs the migration plan on a SchemaV1 store in a temporary folder, the way
/// the app opens the user's library after an update.
@MainActor
struct MigrationTests {
    @Test func v1RatingsBecomeStarsAndEverythingElseStays() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: LibraryLocation.storeFileName)

        let bookID = UUID()
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = container.mainContext
            let book = SchemaV1.Book()
            book.id = bookID
            book.title = "Buddenbrooks"
            book.isbnText = "9783150115374"
            context.insert(book)
            for (index, rating) in [4, nil, 1].enumerated() {
                let reading = SchemaV1.Reading()
                reading.statusRaw = "finished"
                reading.rating = rating
                reading.createdAt = Date(timeIntervalSince1970: Double(index))
                context.insert(reading)
                reading.book = book
            }
            try context.save()
        }

        let container = try LibraryContainer.make(at: url)
        let library = Library(context: container.mainContext)
        let book = try #require(library.fetchBooks().first)
        #expect(book.id == bookID && book.title == "Buddenbrooks")
        let stars = (book.readings ?? []).sorted { $0.createdAt < $1.createdAt }.map(\.stars)
        #expect(stars == [4.0, nil, 1.0])
        #expect((book.readings ?? []).compactMap(\.rating).sorted() == [1, 4])
        #expect(book.displayRating == 1.0)
    }
}
