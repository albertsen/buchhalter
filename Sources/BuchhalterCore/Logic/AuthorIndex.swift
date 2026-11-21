import Foundation

/// One row of Authors: an author with at least one book.
public struct AuthorEntry: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var sortName: String
    public var bookCount: Int

    public init(id: UUID, name: String, sortName: String, bookCount: Int) {
        self.id = id
        self.name = name
        self.sortName = sortName
        self.bookCount = bookCount
    }
}

/// The authors under one letter of their sort names.
public struct AuthorSection: Identifiable, Equatable, Sendable {
    /// "A" to "Z", or `AuthorIndex.otherLetter`.
    public var letter: String
    public var authors: [AuthorEntry]

    public var id: String { letter }
}

/// Authors and an author's books, computed from the fetched books like
/// `LibraryLists`. Authors come from the books' authorships, so an author
/// without books (kept in the store, see architecture.md) is never listed.
public enum AuthorIndex {
    /// The section for sort names that do not start with A to Z after folding:
    /// digits, punctuation, Cyrillic or Greek letters. It comes last.
    public static let otherLetter = "#"

    /// What an author is ordered and grouped by: the sort name, or the name
    /// when the sort name is empty.
    static func sortKey(name: String, sortName: String) -> String {
        let trimmed = sortName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    }

    /// "Mann, Thomas" → "M", "Ärger, …" → "A", "1984 Kollektiv" → "#".
    public static func letter(for sortKey: String) -> String {
        guard let first = TextFolding.fold(sortKey).first else { return otherLetter }
        let upper = String(first).uppercased()
        guard upper.count == 1, let scalar = upper.unicodeScalars.first,
              upper.unicodeScalars.count == 1, ("A"..."Z").contains(scalar) else { return otherLetter }
        return upper
    }

    /// Every author with at least one book, in the order of Authors: by
    /// section (`#` last), then by sort name with German collation, then by
    /// name, then by id so the order never depends on the fetch.
    @MainActor
    public static func authors(in books: [Book]) -> [AuthorEntry] {
        var counts: [UUID: Int] = [:]
        var authors: [UUID: Author] = [:]
        for book in books {
            var seen = Set<UUID>()
            for author in book.orderedAuthors where seen.insert(author.id).inserted {
                counts[author.id, default: 0] += 1
                authors[author.id] = author
            }
        }
        let entries = authors.values.map {
            AuthorEntry(id: $0.id, name: $0.name, sortName: $0.sortName, bookCount: counts[$0.id] ?? 0)
        }
        return entries.sorted(by: areInOrder)
    }

    static func areInOrder(_ a: AuthorEntry, _ b: AuthorEntry) -> Bool {
        let keyA = sortKey(name: a.name, sortName: a.sortName)
        let keyB = sortKey(name: b.name, sortName: b.sortName)
        let otherA = letter(for: keyA) == otherLetter
        let otherB = letter(for: keyB) == otherLetter
        if otherA != otherB { return otherB }
        let bySortName = TextFolding.compare(keyA, keyB)
        if bySortName != .orderedSame { return bySortName == .orderedAscending }
        let byName = TextFolding.compare(a.name, b.name)
        if byName != .orderedSame { return byName == .orderedAscending }
        return a.id.uuidString < b.id.uuidString
    }

    /// Ordered entries grouped by letter; the order of `entries` is kept.
    public static func sections(_ entries: [AuthorEntry]) -> [AuthorSection] {
        var result: [AuthorSection] = []
        for entry in entries {
            let letter = letter(for: sortKey(name: entry.name, sortName: entry.sortName))
            if result.last?.letter == letter {
                result[result.count - 1].authors.append(entry)
            } else {
                result.append(AuthorSection(letter: letter, authors: [entry]))
            }
        }
        return result
    }

    /// Every whitespace-separated token must appear in the name or the sort
    /// name, ignoring case and accents: "boll" finds Heinrich Böll.
    public static func filter(_ entries: [AuthorEntry], query: String) -> [AuthorEntry] {
        let tokens = TextFolding.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return entries }
        return entries.filter { entry in
            let haystack = TextFolding.fold(entry.name + " " + entry.sortName)
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    /// The author's books, oldest first by Year Published. Books from the same
    /// year go by title (without a leading article), books without a year last
    /// (`BookSorter`'s tie and missing-value rules).
    @MainActor
    public static func books(by authorID: UUID, in books: [Book]) -> [Book] {
        let own = books.filter { book in
            (book.authorships ?? []).contains { $0.author?.id == authorID }
        }
        return BookSorter.sorted(own, by: SortLevels(levels: [SortLevel(field: .year)]))
    }

    /// The book's other authors, in their order on the book.
    @MainActor
    public static func coauthors(of book: Book, excluding authorID: UUID) -> [String] {
        book.orderedAuthors.filter { $0.id != authorID }.map(\.name)
    }
}
