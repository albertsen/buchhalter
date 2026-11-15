import Foundation
import SwiftData

// MARK: Records

/// Value copies of the stored objects, used to undo and redo changes.
///
/// SwiftData's own undo reverts values in memory but never marks the context
/// dirty (macOS 27.2): nothing is saved, and the next fetch brings the old
/// value back. So `Library` records what an action changed as plain values and
/// writes them back itself (see `Library.change`).
protocol LibraryRecord: Equatable, Sendable {
    var id: UUID { get }
}

/// A cover is only read for books an operation says it may change: loading
/// every cover for every action would read all external-storage files.
enum CoverState: Equatable, Sendable {
    case untracked
    case tracked(Data?)
}

struct BookRecord: LibraryRecord {
    var id: UUID
    var title: String
    var subtitle: String?
    var isbn13: String?
    var isbnText: String?
    var publisher: String?
    var year: Int?
    var pageCount: Int?
    var language: String?
    var originalLanguage: String?
    var addedAt: Date
    var originRaw: String
    var originNote: String?
    var collectionIDs: Set<UUID>
    var cover: CoverState
}

struct AuthorRecord: LibraryRecord {
    var id: UUID
    var name: String
    var sortName: String
}

struct AuthorshipRecord: LibraryRecord {
    var id: UUID
    var position: Int
    var bookID: UUID?
    var authorID: UUID?
}

struct ReadingRecord: LibraryRecord {
    var id: UUID
    var statusRaw: String
    var startedAt: Date?
    var endedAt: Date?
    var stars: Double?
    var notes: String?
    var createdAt: Date
    var bookID: UUID?
}

struct SettingsRecord: Equatable, Sendable {
    var key: String
    var sortLevelsRaw: String
    var viewModeRaw: String
    var updatedAt: Date
}

struct CollectionRecord: LibraryRecord {
    var id: UUID
    var name: String
    var note: String?
    var sortIndex: Double
    var createdAt: Date
    var settings: SettingsRecord?
}

// MARK: Snapshot

/// Everything the library holds, except covers that are not tracked.
struct LibrarySnapshot: Equatable, Sendable {
    var books: [UUID: BookRecord] = [:]
    var authors: [UUID: AuthorRecord] = [:]
    var authorships: [UUID: AuthorshipRecord] = [:]
    var readings: [UUID: ReadingRecord] = [:]
    var collections: [UUID: CollectionRecord] = [:]

    /// - Parameters:
    ///   - coverIDs: books whose cover bytes are read.
    ///   - newBooksNotIn: when set, covers are also read for books not in this set (books added by the action).
    @MainActor
    static func capture(
        _ context: ModelContext, coverIDs: Set<UUID>, newBooksNotIn known: Set<UUID>? = nil
    ) -> LibrarySnapshot {
        var snapshot = LibrarySnapshot()
        for book in (try? context.fetch(FetchDescriptor<Book>())) ?? [] {
            let tracked = coverIDs.contains(book.id) || (known.map { !$0.contains(book.id) } ?? false)
            snapshot.books[book.id] = BookRecord(
                id: book.id, title: book.title, subtitle: book.subtitle, isbn13: book.isbn13,
                isbnText: book.isbnText, publisher: book.publisher, year: book.year,
                pageCount: book.pageCount, language: book.language,
                originalLanguage: book.originalLanguage, addedAt: book.addedAt,
                originRaw: book.originRaw, originNote: book.originNote,
                collectionIDs: Set((book.collections ?? []).map(\.id)),
                cover: tracked ? .tracked(book.coverImage) : .untracked
            )
        }
        for author in (try? context.fetch(FetchDescriptor<Author>())) ?? [] {
            snapshot.authors[author.id] = AuthorRecord(id: author.id, name: author.name, sortName: author.sortName)
        }
        for item in (try? context.fetch(FetchDescriptor<Authorship>())) ?? [] {
            snapshot.authorships[item.id] = AuthorshipRecord(
                id: item.id, position: item.position, bookID: item.book?.id, authorID: item.author?.id
            )
        }
        for reading in (try? context.fetch(FetchDescriptor<Reading>())) ?? [] {
            snapshot.readings[reading.id] = ReadingRecord(
                id: reading.id, statusRaw: reading.statusRaw, startedAt: reading.startedAt,
                endedAt: reading.endedAt, stars: reading.stars, notes: reading.notes,
                createdAt: reading.createdAt, bookID: reading.book?.id
            )
        }
        for collection in (try? context.fetch(FetchDescriptor<Collection>())) ?? [] {
            snapshot.collections[collection.id] = CollectionRecord(
                id: collection.id, name: collection.name, note: collection.note,
                sortIndex: collection.sortIndex, createdAt: collection.createdAt,
                settings: collection.settings.map {
                    SettingsRecord(
                        key: $0.key, sortLevelsRaw: $0.sortLevelsRaw,
                        viewModeRaw: $0.viewModeRaw, updatedAt: $0.updatedAt
                    )
                }
            )
        }
        return snapshot
    }
}

// MARK: Diff

/// What it takes to turn one snapshot into another: records to create,
/// records to delete, and old/new pairs of records to change.
struct Changes<R: LibraryRecord>: Sendable {
    var inserted: [R] = []
    var deleted: [R] = []
    var updated: [(old: R, new: R)] = []

    var isEmpty: Bool { inserted.isEmpty && deleted.isEmpty && updated.isEmpty }

    init(from old: [UUID: R], to new: [UUID: R]) {
        for (id, record) in new {
            if let previous = old[id] {
                if previous != record { updated.append((previous, record)) }
            } else {
                inserted.append(record)
            }
        }
        deleted = old.filter { new[$0.key] == nil }.map(\.value)
    }
}

struct LibraryDiff: Sendable {
    var books: Changes<BookRecord>
    var authors: Changes<AuthorRecord>
    var authorships: Changes<AuthorshipRecord>
    var readings: Changes<ReadingRecord>
    var collections: Changes<CollectionRecord>

    /// The changes that turn `old` into `new`.
    init(from old: LibrarySnapshot, to new: LibrarySnapshot) {
        books = Changes(from: old.books, to: new.books)
        authors = Changes(from: old.authors, to: new.authors)
        authorships = Changes(from: old.authorships, to: new.authorships)
        readings = Changes(from: old.readings, to: new.readings)
        collections = Changes(from: old.collections, to: new.collections)
    }

    var isEmpty: Bool {
        books.isEmpty && authors.isEmpty && authorships.isEmpty && readings.isEmpty && collections.isEmpty
    }
}

// MARK: Applying a diff

@MainActor
extension Library {
    /// Writes a diff into the context: creates, changes and deletes objects so
    /// the library matches the diff's target snapshot. Only fields that differ
    /// between a pair's old and new record are written, so unrelated later
    /// changes survive. Does not save.
    func apply(_ diff: LibraryDiff) {
        var books = index(Book.self) { $0.id }
        var authors = index(Author.self) { $0.id }
        var authorships = index(Authorship.self) { $0.id }
        var readings = index(Reading.self) { $0.id }
        var collections = index(Collection.self) { $0.id }

        // Create parents first, then what points at them.
        for record in diff.authors.inserted {
            let author = Author()
            author.id = record.id
            author.name = record.name
            author.sortName = record.sortName
            context.insert(author)
            authors[record.id] = author
        }
        for record in diff.collections.inserted {
            let collection = Collection()
            collection.id = record.id
            collection.name = record.name
            collection.note = record.note
            collection.sortIndex = record.sortIndex
            collection.createdAt = record.createdAt
            context.insert(collection)
            if let settings = record.settings { collection.settings = makeSettings(settings) }
            collections[record.id] = collection
        }
        for record in diff.books.inserted {
            let book = Book()
            book.id = record.id
            book.title = record.title
            book.subtitle = record.subtitle
            book.isbn13 = record.isbn13
            book.isbnText = record.isbnText
            book.publisher = record.publisher
            book.year = record.year
            book.pageCount = record.pageCount
            book.language = record.language
            book.originalLanguage = record.originalLanguage
            book.addedAt = record.addedAt
            book.originRaw = record.originRaw
            book.originNote = record.originNote
            if case .tracked(let data) = record.cover { book.coverImage = data }
            context.insert(book)
            book.collections = record.collectionIDs.compactMap { collections[$0] }
            books[record.id] = book
        }
        for record in diff.readings.inserted {
            let reading = Reading()
            reading.id = record.id
            reading.statusRaw = record.statusRaw
            reading.startedAt = record.startedAt
            reading.endedAt = record.endedAt
            reading.stars = record.stars
            reading.notes = record.notes
            reading.createdAt = record.createdAt
            context.insert(reading)
            reading.book = record.bookID.flatMap { books[$0] }
            readings[record.id] = reading
        }
        for record in diff.authorships.inserted {
            let authorship = Authorship()
            authorship.id = record.id
            authorship.position = record.position
            context.insert(authorship)
            authorship.book = record.bookID.flatMap { books[$0] }
            authorship.author = record.authorID.flatMap { authors[$0] }
            authorships[record.id] = authorship
        }

        // Change what exists.
        for (old, new) in diff.authors.updated {
            guard let author = authors[new.id] else { continue }
            if old.name != new.name { author.name = new.name }
            if old.sortName != new.sortName { author.sortName = new.sortName }
        }
        for (old, new) in diff.collections.updated {
            guard let collection = collections[new.id] else { continue }
            if old.name != new.name { collection.name = new.name }
            if old.note != new.note { collection.note = new.note }
            if old.sortIndex != new.sortIndex { collection.sortIndex = new.sortIndex }
            if old.createdAt != new.createdAt { collection.createdAt = new.createdAt }
            if old.settings != new.settings {
                if let existing = collection.settings { context.delete(existing) }
                collection.settings = new.settings.map(makeSettings)
            }
        }
        for (old, new) in diff.books.updated {
            guard let book = books[new.id] else { continue }
            if old.title != new.title { book.title = new.title }
            if old.subtitle != new.subtitle { book.subtitle = new.subtitle }
            if old.isbn13 != new.isbn13 { book.isbn13 = new.isbn13 }
            if old.isbnText != new.isbnText { book.isbnText = new.isbnText }
            if old.publisher != new.publisher { book.publisher = new.publisher }
            if old.year != new.year { book.year = new.year }
            if old.pageCount != new.pageCount { book.pageCount = new.pageCount }
            if old.language != new.language { book.language = new.language }
            if old.originalLanguage != new.originalLanguage { book.originalLanguage = new.originalLanguage }
            if old.addedAt != new.addedAt { book.addedAt = new.addedAt }
            if old.originRaw != new.originRaw { book.originRaw = new.originRaw }
            if old.originNote != new.originNote { book.originNote = new.originNote }
            if old.cover != new.cover, case .tracked(let data) = new.cover { book.coverImage = data }
            for id in new.collectionIDs.subtracting(old.collectionIDs) {
                if let collection = collections[id], !(book.collections ?? []).contains(where: { $0 === collection }) {
                    book.collections?.append(collection)
                }
            }
            for id in old.collectionIDs.subtracting(new.collectionIDs) {
                book.collections?.removeAll { $0.id == id }
            }
        }
        for (old, new) in diff.readings.updated {
            guard let reading = readings[new.id] else { continue }
            if old.statusRaw != new.statusRaw { reading.statusRaw = new.statusRaw }
            if old.startedAt != new.startedAt { reading.startedAt = new.startedAt }
            if old.endedAt != new.endedAt { reading.endedAt = new.endedAt }
            if old.stars != new.stars { reading.stars = new.stars }
            if old.notes != new.notes { reading.notes = new.notes }
            if old.createdAt != new.createdAt { reading.createdAt = new.createdAt }
            if old.bookID != new.bookID { reading.book = new.bookID.flatMap { books[$0] } }
        }
        for (old, new) in diff.authorships.updated {
            guard let authorship = authorships[new.id] else { continue }
            if old.position != new.position { authorship.position = new.position }
            if old.bookID != new.bookID { authorship.book = new.bookID.flatMap { books[$0] } }
            if old.authorID != new.authorID { authorship.author = new.authorID.flatMap { authors[$0] } }
        }

        // Delete leaves before their parents, so a cascade finds nothing left to do.
        for record in diff.authorships.deleted { authorships[record.id].map(context.delete) }
        for record in diff.readings.deleted { readings[record.id].map(context.delete) }
        for record in diff.books.deleted { books[record.id].map(context.delete) }
        for record in diff.collections.deleted { collections[record.id].map(context.delete) }
        for record in diff.authors.deleted { authors[record.id].map(context.delete) }
    }

    private func makeSettings(_ record: SettingsRecord) -> ListSettings {
        let settings = ListSettings()
        settings.key = record.key
        settings.sortLevelsRaw = record.sortLevelsRaw
        settings.viewModeRaw = record.viewModeRaw
        settings.updatedAt = record.updatedAt
        context.insert(settings)
        return settings
    }

    private func index<M: PersistentModel>(_ type: M.Type, id: (M) -> UUID) -> [UUID: M] {
        var result: [UUID: M] = [:]
        for object in (try? context.fetch(FetchDescriptor<M>())) ?? [] { result[id(object)] = object }
        return result
    }
}
