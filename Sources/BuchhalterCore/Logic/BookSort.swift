import Foundation

/// A sortable property of a book.
public enum SortField: String, CaseIterable, Sendable {
    case author, title, year, dateAdded, dateStarted, dateFinished, rating, pages

    /// What the toolbar button shows: "Sort: Author, Year".
    public var shortName: LocalizedStringResource {
        switch self {
        case .author: "Author"
        case .title: "Title"
        case .year: "Year"
        case .dateAdded: "Added"
        case .dateStarted: "Started"
        case .dateFinished: LocalizedStringResource("sortField.finished", defaultValue: "Finished")
        case .rating: "Rating"
        case .pages: "Pages"
        }
    }

    /// What the popover's field menu shows.
    public var longName: LocalizedStringResource {
        switch self {
        case .author: "Author"
        case .title: "Title"
        case .year: "Year Published"
        case .dateAdded: "Date Added"
        case .dateStarted: "Date Started"
        case .dateFinished: "Date Finished"
        case .rating: "Rating"
        case .pages: "Pages"
        }
    }

    enum Kind { case text, date, number }

    var kind: Kind {
        switch self {
        case .author, .title: .text
        case .year, .dateAdded, .dateStarted, .dateFinished: .date
        case .rating, .pages: .number
        }
    }

    public func name(for direction: SortDirection) -> LocalizedStringResource {
        switch (kind, direction) {
        case (.text, .ascending): "A to Z"
        case (.text, .descending): "Z to A"
        case (.date, .ascending): "Oldest first"
        case (.date, .descending): "Newest first"
        case (.number, .ascending): "Lowest first"
        case (.number, .descending): "Highest first"
        }
    }
}

public enum SortDirection: String, CaseIterable, Sendable {
    case ascending = "asc"
    case descending = "desc"
}

public struct SortLevel: Equatable, Sendable {
    public var field: SortField
    public var direction: SortDirection

    public init(field: SortField, direction: SortDirection = .ascending) {
        self.field = field
        self.direction = direction
    }
}

/// The ordered sort levels of one list, stored as a string such as
/// `"author:asc,year:asc"`. Unknown fields from a newer app version are
/// skipped, each field appears at most once, and the first level cannot be
/// removed.
public struct SortLevels: Equatable, Sendable {
    public private(set) var levels: [SortLevel]

    public static let `default` = SortLevels(levels: [
        SortLevel(field: .author, direction: .ascending),
        SortLevel(field: .year, direction: .ascending),
    ])

    public init(levels: [SortLevel]) {
        var seen = Set<SortField>()
        var result: [SortLevel] = []
        for level in levels where seen.insert(level.field).inserted {
            result.append(level)
        }
        self.levels = result.isEmpty ? Self.default.levels : result
    }

    /// An empty or unreadable string gives the default.
    public init(raw: String) {
        var parsed: [SortLevel] = []
        for part in raw.split(separator: ",") {
            let pieces = part.split(separator: ":")
            guard let first = pieces.first, let field = SortField(rawValue: String(first)) else { continue }
            let direction = pieces.count > 1 ? SortDirection(rawValue: String(pieces[1])) : .ascending
            parsed.append(SortLevel(field: field, direction: direction ?? .ascending))
        }
        self.init(levels: parsed)
    }

    public var raw: String {
        levels.map { "\($0.field.rawValue):\($0.direction.rawValue)" }.joined(separator: ",")
    }

    public var isDefault: Bool { self == .default }

    public var availableFields: [SortField] {
        let used = Set(levels.map(\.field))
        return SortField.allCases.filter { !used.contains($0) }
    }

    public var canAdd: Bool { !availableFields.isEmpty }

    /// Adds the first unused field, ascending.
    public func adding() -> SortLevels {
        guard let field = availableFields.first else { return self }
        return SortLevels(levels: levels + [SortLevel(field: field)])
    }

    /// The first level cannot be removed.
    public func removing(at index: Int) -> SortLevels {
        guard index > 0, levels.indices.contains(index) else { return self }
        var copy = levels
        copy.remove(at: index)
        return SortLevels(levels: copy)
    }

    /// Replaces the field of a level, keeping the other levels free of duplicates.
    public func setting(field: SortField, at index: Int) -> SortLevels {
        guard levels.indices.contains(index) else { return self }
        var copy = levels
        copy[index].field = field
        // A field already used by another level moves out of the way.
        copy = copy.enumerated().filter { $0.offset == index || $0.element.field != field }.map(\.element)
        return SortLevels(levels: copy)
    }

    public func setting(direction: SortDirection, at index: Int) -> SortLevels {
        guard levels.indices.contains(index) else { return self }
        var copy = levels
        copy[index].direction = direction
        return SortLevels(levels: copy)
    }
}

/// Everything the comparator needs from one book, as plain values.
public struct BookSortKey: Sendable {
    public var id: UUID
    public var authorSortName: String?
    public var titleKey: String
    public var year: Int?
    public var addedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var rating: Double?
    public var pages: Int?

    public init(
        id: UUID = UUID(), authorSortName: String? = nil, titleKey: String,
        year: Int? = nil, addedAt: Date = .distantPast, startedAt: Date? = nil,
        finishedAt: Date? = nil, rating: Double? = nil, pages: Int? = nil
    ) {
        self.id = id
        self.authorSortName = authorSortName
        self.titleKey = titleKey
        self.year = year
        self.addedAt = addedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.rating = rating
        self.pages = pages
    }
}

public enum BookSorter {
    /// A missing value sorts last in both directions. Ties go to the title key,
    /// then `addedAt`, then `id`.
    public static func areInOrder(_ a: BookSortKey, _ b: BookSortKey, by levels: SortLevels) -> Bool {
        for level in levels.levels {
            let result = compare(a, b, field: level.field, direction: level.direction)
            if result != .orderedSame { return result == .orderedAscending }
        }
        let title = TextFolding.compare(a.titleKey, b.titleKey)
        if title != .orderedSame { return title == .orderedAscending }
        if a.addedAt != b.addedAt { return a.addedAt < b.addedAt }
        return a.id.uuidString < b.id.uuidString
    }

    private static func compare(
        _ a: BookSortKey, _ b: BookSortKey, field: SortField, direction: SortDirection
    ) -> ComparisonResult {
        switch field {
        case .author: compareOptional(a.authorSortName, b.authorSortName, direction, TextFolding.compare)
        case .title: orient(TextFolding.compare(a.titleKey, b.titleKey), direction)
        case .year: compareOptional(a.year, b.year, direction, ordered)
        case .dateAdded: orient(ordered(a.addedAt, b.addedAt), direction)
        case .dateStarted: compareOptional(a.startedAt, b.startedAt, direction, ordered)
        case .dateFinished: compareOptional(a.finishedAt, b.finishedAt, direction, ordered)
        case .rating: compareOptional(a.rating, b.rating, direction, ordered)
        case .pages: compareOptional(a.pages, b.pages, direction, ordered)
        }
    }

    private static func ordered<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }

    private static func orient(_ result: ComparisonResult, _ direction: SortDirection) -> ComparisonResult {
        guard direction == .descending else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    private static func compareOptional<T>(
        _ a: T?, _ b: T?, _ direction: SortDirection, _ compare: (T, T) -> ComparisonResult
    ) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (x?, y?): return orient(compare(x, y), direction)
        }
    }
}

extension BookSortKey {
    @MainActor
    public init(book: Book) {
        self.init(
            id: book.id,
            authorSortName: book.orderedAuthors.first?.sortName,
            titleKey: TextFolding.titleSortKey(book.title),
            year: book.year,
            addedAt: book.addedAt,
            startedAt: book.latestStartedAt,
            finishedAt: book.latestFinishedAt,
            rating: book.displayRating,
            pages: book.pageCount
        )
    }
}

extension BookSorter {
    @MainActor
    public static func sorted(_ books: [Book], by levels: SortLevels) -> [Book] {
        let keyed = books.map { (book: $0, key: BookSortKey(book: $0)) }
        return keyed.sorted { areInOrder($0.key, $1.key, by: levels) }.map(\.book)
    }
}
