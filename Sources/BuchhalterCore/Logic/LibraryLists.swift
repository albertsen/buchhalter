import Foundation

/// A list in the sidebar. The four built-in lists are computed from the
/// books' current readings, never stored (Decision 4). Authors lists authors,
/// not books (`AuthorIndex`): it is not in `builtIn`, has no `ListSettings`
/// and contains no book.
public enum LibraryListID: Hashable, Sendable, RawRepresentable, Codable {
    case reading, wantToRead, read, all
    case authors
    case collection(UUID)

    public init?(rawValue: String) {
        switch rawValue {
        case "reading": self = .reading
        case "wantToRead": self = .wantToRead
        case "read": self = .read
        case "all": self = .all
        case "authors": self = .authors
        default:
            guard rawValue.hasPrefix("collection:"),
                  let id = UUID(uuidString: String(rawValue.dropFirst("collection:".count)))
            else { return nil }
            self = .collection(id)
        }
    }

    public var rawValue: String {
        switch self {
        case .reading: "reading"
        case .wantToRead: "wantToRead"
        case .read: "read"
        case .all: "all"
        case .authors: "authors"
        case .collection(let id): "collection:\(id.uuidString)"
        }
    }

    /// The `ListSettings.key` of a built-in list; empty for a collection.
    public var settingsKey: String {
        if case .collection = self { return "" }
        return rawValue
    }

    /// The name of a built-in list. A collection's name is the user's own.
    public var builtInName: LocalizedStringResource? {
        switch self {
        case .reading: "Reading"
        case .wantToRead: "Want to Read"
        case .read: "Read"
        case .all: "All Books"
        case .authors: "Authors"
        case .collection: nil
        }
    }

    /// The four lists of books. Authors is a sidebar list too, but not one of these.
    public static let builtIn: [LibraryListID] = [.reading, .wantToRead, .read, .all]
}

public enum LibraryLists {
    @MainActor
    public static func contains(_ book: Book, in list: LibraryListID) -> Bool {
        switch list {
        case .all: true
        case .reading: book.status == .reading
        case .wantToRead: book.status == .wantToRead
        case .read: book.status == .finished
        case .authors: false
        case .collection(let id): (book.collections ?? []).contains { $0.id == id }
        }
    }

    @MainActor
    public static func books(in list: LibraryListID, from books: [Book]) -> [Book] {
        books.filter { contains($0, in: list) }
    }

    /// Counts for every built-in list and every collection, in one pass, and
    /// for Authors the number of authors with at least one book.
    @MainActor
    public static func counts(books: [Book], collections: [Collection]) -> [LibraryListID: Int] {
        var result: [LibraryListID: Int] = [.reading: 0, .wantToRead: 0, .read: 0, .all: books.count]
        for collection in collections { result[.collection(collection.id)] = 0 }
        var authors = Set<UUID>()
        for book in books {
            for authorship in book.authorships ?? [] {
                if let author = authorship.author { authors.insert(author.id) }
            }
            switch book.status {
            case .reading: result[.reading, default: 0] += 1
            case .wantToRead: result[.wantToRead, default: 0] += 1
            case .finished: result[.read, default: 0] += 1
            case .abandoned, nil: break
            }
            for collection in book.collections ?? [] {
                result[.collection(collection.id), default: 0] += 1
            }
        }
        result[.authors] = authors.count
        return result
    }
}
