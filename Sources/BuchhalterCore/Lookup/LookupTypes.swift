import Foundation

/// The services Complete asks, in the order it asks them.
public enum LookupSource: String, Sendable {
    case dnb, openLibrary
}

/// What Complete searches for, built from the sheet's draft.
public enum LookupQuery: Equatable, Sendable {
    /// `display` is the user's own text, for the status line and the hints.
    case isbn(ISBN, display: String)
    case titleAuthor(title: String, authors: [AuthorDraft])

    /// A valid ISBN wins. Otherwise a title and at least one author give a
    /// title-and-author search, counting the author text not yet turned into a
    /// chip. Anything else is nil, which disables Complete. An invalid or
    /// incomplete ISBN is ignored.
    public init?(draft: BookDraft, pendingAuthor: String = "") {
        if case .valid(let isbn) = ISBN.parse(draft.isbnText) {
            self = .isbn(isbn, display: draft.isbnText.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
        let title = AuthorName.normalize(draft.title)
        var authors = draft.authors.filter { !AuthorName.normalize($0.name).isEmpty }
        let pending = AuthorName.normalize(pendingAuthor)
        if !pending.isEmpty, !authors.contains(where: { AuthorName.matchKey($0.name) == AuthorName.matchKey(pending) }) {
            authors.append(AuthorDraft(name: pending, sortName: AuthorName.guessSortName(pending)))
        }
        guard !title.isEmpty, !authors.isEmpty else { return nil }
        self = .titleAuthor(title: title, authors: authors)
    }

    /// The typed ISBN as the user wrote it. Empty for a title-and-author search.
    public var isbnDisplay: String {
        if case .isbn(_, let display) = self { display } else { "" }
    }
}

public struct LookupAuthor: Equatable, Sendable {
    public var name: String
    /// The sort name when the source gave an inverted heading; nil when it has to be guessed.
    public var sortName: String?

    public init(name: String, sortName: String? = nil) {
        self.name = name
        self.sortName = sortName
    }
}

/// Where a record's cover comes from. Downloading goes through the service.
public enum CoverReference: Equatable, Sendable {
    case dnb(isbn13: String)
    case openLibrary(coverID: Int)
}

public enum CoverSize: Sendable {
    case small, large
}

/// One edition a service found, in the shape both services share.
public struct LookupRecord: Identifiable, Equatable, Sendable {
    /// "dnb:<001>" or "openlibrary:<edition key>". Also stored as the book's origin note.
    public var id: String
    public var source: LookupSource
    /// With the non-sort markers removed ("The Buddenbrooks").
    public var title: String
    /// Folded forms the typed title is compared with: with and without the non-sort part.
    public var titleMatchKeys: [String]
    public var subtitle: String?
    public var authors: [LookupAuthor]
    public var year: Int?
    public var pages: Int?
    /// ISO 639-1 codes.
    public var language: String?
    public var originalLanguage: String?
    public var publisher: String?
    /// Every ISBN of the record, as ISBN-13.
    public var isbn13s: [String]
    public var isbnDisplay: String?
    public var cover: CoverReference?

    public init(
        id: String, source: LookupSource, title: String, titleMatchKeys: [String]? = nil,
        subtitle: String? = nil, authors: [LookupAuthor] = [], year: Int? = nil, pages: Int? = nil,
        language: String? = nil, originalLanguage: String? = nil, publisher: String? = nil,
        isbn13s: [String] = [], isbnDisplay: String? = nil, cover: CoverReference? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.titleMatchKeys = titleMatchKeys ?? [TextFolding.fold(AuthorName.normalize(title))]
        self.subtitle = subtitle
        self.authors = authors
        self.year = year
        self.pages = pages
        self.language = language
        self.originalLanguage = originalLanguage
        self.publisher = publisher
        self.isbn13s = isbn13s
        self.isbnDisplay = isbnDisplay
        self.cover = cover
    }
}

/// What a service returned: the records after the carrier filter and before
/// the match filter, and the service's own total.
public struct LookupResponse: Sendable {
    public var records: [LookupRecord]
    public var totalCount: Int

    public init(records: [LookupRecord], totalCount: Int) {
        self.records = records
        self.totalCount = totalCount
    }
}

public enum LookupError: Error, Equatable, Sendable {
    /// No connection, timeout, an HTTP status other than 200, a body that
    /// cannot be read, or an SRU diagnostic.
    case unreachable(LookupSource)
}
