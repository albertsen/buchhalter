import Foundation

/// The book sources. The user decides which are on and in which order
/// Complete and Find Cover ask them (`LookupSourceList`).
public enum LookupSource: String, CaseIterable, Sendable {
    case dnb, openLibrary, googleBooks

    /// The source's own name, which is never translated. The Settings rows use it.
    public var displayName: String {
        switch self {
        case .dnb: "Deutsche Nationalbibliothek"
        case .openLibrary: "Open Library"
        case .googleBooks: "Google Books"
        }
    }

    /// How many records a service returns at most. A list as long as this may
    /// have lost older records. Google's own total is an estimate and its
    /// answers are capped at 40, so its lists are never called truncated.
    public var maximumListedRecords: Int? {
        switch self {
        case .dnb: DNBService.maximumRecords
        case .openLibrary: OpenLibraryService.maximumRecords
        case .googleBooks: nil
        }
    }
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

    /// The searches Find Cover runs, in order: the ISBN when it is valid, then
    /// title and authors. The cover search cuts the title at the first colon
    /// or parenthesis ("Galveston: A Novel", "On the Road (Penguin Classics)"),
    /// because a match needs the record's title to start with the typed one.
    public static func coverQueries(for draft: BookDraft) -> [LookupQuery] {
        var result: [LookupQuery] = []
        if case .valid(let isbn) = ISBN.parse(draft.isbnText) {
            result.append(.isbn(isbn, display: draft.isbnText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        let full = AuthorName.normalize(draft.title)
        let cut = full.firstIndex { $0 == ":" || $0 == "(" }.map { AuthorName.normalize(String(full[..<$0])) } ?? full
        let title = cut.isEmpty ? full : cut
        let authors = draft.authors.filter { !AuthorName.normalize($0.name).isEmpty }
        if !title.isEmpty, !authors.isEmpty {
            result.append(.titleAuthor(title: title, authors: authors))
        }
        return result
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
    /// The large image is found through the volume, see `GoogleBooksService`.
    case googleBooks(volumeID: String)
}

/// Where a record's synopsis comes from. Only `.text` is in the search
/// answer; the others are downloaded through the service when used.
public enum SynopsisReference: Equatable, Sendable {
    /// Already plain text: Google Books' description, a DNB summary (520).
    case text(String)
    /// The publisher's blurb the DNB links for the record (856, "Inhaltstext").
    case dnbBlurb(URL)
    /// The Open Library work, whose description may be missing.
    case openLibraryWork(key: String)
}

/// A synopsis found for a book, with the source that had it.
public struct Synopsis: Equatable, Sendable {
    public var text: String
    public var source: LookupSource

    public init(text: String, source: LookupSource) {
        self.text = text
        self.source = source
    }
}

public enum CoverSize: Sendable {
    case small, large
}

/// One edition a service found, in the shape both services share.
public struct LookupRecord: Identifiable, Equatable, Sendable {
    /// "dnb:<001>", "openlibrary:<edition key>" or "googlebooks:<volume id>". Also stored as the book's origin note.
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
    /// Open Library: the work's cover, which may belong to another edition of
    /// the same book. Only Find Cover uses it, after the edition's own.
    public var workCover: CoverReference?
    /// Google Books: the book's page there, which the edition list must link to.
    public var webPage: URL?
    public var synopsis: SynopsisReference?
    /// The synopsis's language, taken from the edition's (the sources tag the
    /// edition, not the text). Open Library's work text is untagged: nil.
    public var synopsisLanguage: String? {
        if case .openLibraryWork = synopsis { nil } else { language }
    }

    public init(
        id: String, source: LookupSource, title: String, titleMatchKeys: [String]? = nil,
        subtitle: String? = nil, authors: [LookupAuthor] = [], year: Int? = nil, pages: Int? = nil,
        language: String? = nil, originalLanguage: String? = nil, publisher: String? = nil,
        isbn13s: [String] = [], isbnDisplay: String? = nil, cover: CoverReference? = nil,
        workCover: CoverReference? = nil, webPage: URL? = nil, synopsis: SynopsisReference? = nil
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
        self.workCover = workCover
        self.webPage = webPage
        self.synopsis = synopsis
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

/// Services throw `unreachable` and `keyRejected`; `BookLookup` throws
/// `noSourceReached` when every source it asked has failed.
public enum LookupError: Error, Equatable, Sendable {
    /// No connection, timeout, an HTTP status other than 200, a body that
    /// cannot be read, or an SRU diagnostic.
    case unreachable(LookupSource)
    /// The service refused the user's API key (Google Books): it is invalid,
    /// revoked, restricted from the Books API, or its quota is used up.
    case keyRejected(LookupSource)
    /// Every source that was asked failed. Carries the sources asked, in order.
    case noSourceReached([LookupSource])
}
