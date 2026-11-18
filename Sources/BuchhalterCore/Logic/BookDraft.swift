import Foundation

public enum DraftStatus: String, CaseIterable, Sendable {
    case wantToRead, reading, read
}

public struct AuthorDraft: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var sortName: String
    /// True when the author already exists in the library and `sortName` is its stored one.
    public var isExisting: Bool

    public init(id: UUID = UUID(), name: String, sortName: String, isExisting: Bool = false) {
        self.id = id
        self.name = name
        self.sortName = sortName
        self.isExisting = isExisting
    }
}

public enum DraftIssue: Hashable, Sendable {
    case emptyTitle, invalidISBN, invalidYear, invalidPages, finishBeforeStart
}

/// Every field of the Add and Edit sheet as one value, so the sheet can
/// validate while the user types and the store applies it in one undo step.
public struct BookDraft: Equatable, Sendable {
    public var title = ""
    public var subtitle = ""
    public var authors: [AuthorDraft] = []
    public var yearText = ""
    public var pagesText = ""
    /// ISO 639 code.
    public var language: String?
    /// ISO 639 code of the original, for a translation.
    public var originalLanguage: String?
    public var publisher = ""
    public var isbnText = ""
    public var coverData: Data?
    /// When the book came into the library. Now for a new book; the user can
    /// set an earlier day for books they had before.
    public var addedAt = Date.now
    /// Nil for a book without readings or with an abandoned current reading:
    /// saving then leaves its readings alone.
    public var status: DraftStatus? = .wantToRead
    public var startedAt: Date?
    /// Today for a new finished reading. Nil keeps a finished reading without
    /// a date (the LibraryThing bulk import has 462) undated when the book is saved.
    public var finishedAt: Date? = Calendar.current.startOfDay(for: .now)
    /// Half stars, 0.5 to 5.0.
    public var rating: Double?
    public var notes = ""
    public var collectionIDs: [UUID] = []
    /// Plain text; empty for none.
    public var synopsis = ""
    /// The source the synopsis came from. Nil when it was typed or edited:
    /// the editor clears it on every change to the text.
    public var synopsisSource: LookupSource?

    public init() {}

    public var issues: Set<DraftIssue> {
        var result = Set<DraftIssue>()
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.insert(.emptyTitle) }
        switch ISBN.parse(isbnText) {
        case .empty, .valid: break
        case .incomplete, .invalid: result.insert(.invalidISBN)
        }
        if Self.parseNumber(yearText, range: 1...9999) == .invalid { result.insert(.invalidYear) }
        if Self.parseNumber(pagesText, range: 1...99_999) == .invalid { result.insert(.invalidPages) }
        if status == .read, let start = startedAt, let finish = finishedAt, finish < start { result.insert(.finishBeforeStart) }
        return result
    }

    public var canSave: Bool { issues.isEmpty }

    public var year: Int? { Self.parseNumber(yearText, range: 1...9999).value }
    public var pages: Int? { Self.parseNumber(pagesText, range: 1...99_999).value }

    enum Parsed: Equatable {
        case none, invalid, value(Int)
        var value: Int? { if case .value(let v) = self { v } else { nil } }
    }

    static func parseNumber(_ text: String, range: ClosedRange<Int>) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .none }
        guard trimmed.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(trimmed), range.contains(n) else {
            return .invalid
        }
        return .value(n)
    }
}

extension BookDraft {
    /// Fills the draft for Edit Book.
    @MainActor
    public init(book: Book) {
        self.init()
        title = book.title
        subtitle = book.subtitle ?? ""
        authors = book.orderedAuthors.map {
            AuthorDraft(name: $0.name, sortName: $0.sortName, isExisting: true)
        }
        yearText = book.year.map(String.init) ?? ""
        pagesText = book.pageCount.map(String.init) ?? ""
        language = book.language
        originalLanguage = book.originalLanguage
        publisher = book.publisher ?? ""
        // Books saved before ISBNs were normalized show the hyphenated form too.
        isbnText = ISBN.formatted(book.isbnText ?? "")
        coverData = book.coverImage
        addedAt = book.addedAt
        collectionIDs = (book.collections ?? []).map(\.id)
        synopsis = book.synopsis ?? ""
        synopsisSource = book.synopsisSource
        if let reading = book.currentReading {
            switch reading.status {
            case .wantToRead: status = .wantToRead
            case .reading:
                status = .reading
                startedAt = reading.startedAt ?? Calendar.current.startOfDay(for: .now)
            case .finished:
                status = .read
                startedAt = reading.startedAt
                finishedAt = reading.endedAt
                rating = reading.stars
                notes = reading.notes ?? ""
            case .abandoned:
                status = nil
            }
        } else {
            status = nil
        }
    }
}
