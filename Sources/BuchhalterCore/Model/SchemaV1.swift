import Foundation
import SwiftData

/// The first shipped schema. Once a real library exists, a change to these
/// types needs a `SchemaV2` and a migration stage, never an edit here.
///
/// CloudKit rules hold from the start: every attribute is optional or has a
/// default, no `.unique`, every relationship is optional with an inverse, and
/// no `.deny` delete rules. Enums are stored as `String` raw values.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [Book.self, Author.self, Authorship.self, Reading.self, Collection.self, ListSettings.self]
    }

    // MARK: Book

    @Model
    public final class Book {
        public var id: UUID = UUID()
        public var title: String = ""
        public var subtitle: String?
        /// Normalized ISBN-13 digits, for duplicate matching and search.
        public var isbn13: String?
        /// The user's trimmed input, for display and editing.
        public var isbnText: String?
        public var publisher: String?
        public var year: Int?
        public var pageCount: Int?
        /// ISO 639 code, for example "de".
        public var language: String?
        /// ISO 639 code of the language the book was written in, when it is a
        /// translation. Nil when unknown or the same as `language`.
        public var originalLanguage: String?
        @Attribute(.externalStorage) public var coverImage: Data?
        public var addedAt: Date = Date.now
        public var originRaw: String = "manual"
        public var originNote: String?

        @Relationship(deleteRule: .cascade, inverse: \Authorship.book)
        public var authorships: [Authorship]? = []
        @Relationship(deleteRule: .cascade, inverse: \Reading.book)
        public var readings: [Reading]? = []
        @Relationship(deleteRule: .nullify, inverse: \Collection.books)
        public var collections: [Collection]? = []

        public init() {}
    }

    // MARK: Author

    @Model
    public final class Author {
        public var id: UUID = UUID()
        public var name: String = ""
        /// "Mann, Thomas". One per author, so a correction applies to all their books.
        public var sortName: String = ""

        @Relationship(deleteRule: .cascade, inverse: \Authorship.author)
        public var authorships: [Authorship]? = []

        public init() {}
    }

    // MARK: Authorship

    /// Ordered join between a book and an author. SwiftData's to-many
    /// relationships are unordered, and the first author decides the sort order.
    @Model
    public final class Authorship {
        public var id: UUID = UUID()
        public var position: Int = 0
        public var book: Book?
        public var author: Author?

        public init() {}
    }

    // MARK: Reading

    @Model
    public final class Reading {
        public var id: UUID = UUID()
        public var statusRaw: String = "wantToRead"
        public var startedAt: Date?
        /// The finish or abandon date.
        public var endedAt: Date?
        public var rating: Int?
        public var notes: String?
        public var createdAt: Date = Date.now
        public var book: Book?

        public init() {}
    }

    // MARK: Collection

    @Model
    public final class Collection {
        public var id: UUID = UUID()
        public var name: String = ""
        public var note: String?
        public var sortIndex: Double = 0
        public var createdAt: Date = Date.now
        public var books: [Book]? = []

        @Relationship(deleteRule: .cascade, inverse: \ListSettings.collection)
        public var settings: ListSettings?

        public init() {}
    }

    // MARK: ListSettings

    /// Sort levels and view mode of one list. `key` names a built-in list
    /// ("reading", "wantToRead", "read", "all"); it is empty for a collection's
    /// settings, which hang off `collection`. There is no unique constraint
    /// (CloudKit), so readers take the newest `updatedAt` when duplicates exist.
    @Model
    public final class ListSettings {
        public var key: String = ""
        public var collection: Collection?
        /// Empty means the default order.
        public var sortLevelsRaw: String = ""
        public var viewModeRaw: String = "list"
        public var updatedAt: Date = Date.now

        public init() {}
    }
}
