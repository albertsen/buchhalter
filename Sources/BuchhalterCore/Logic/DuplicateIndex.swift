import Foundation

/// Finds a book in the library that a draft would duplicate: the same ISBN-13,
/// or the same title together with at least one common author.
public struct DuplicateIndex: Sendable {
    public struct Entry: Equatable, Sendable {
        public let bookID: UUID
        public let label: String
        let isbn13: String?
        let titleKey: String
        let authorKeys: Set<String>
    }

    private let entries: [Entry]

    /// Built once when the sheet opens, from all books except the edited one.
    @MainActor
    public init(books: [Book], excluding excluded: UUID? = nil) {
        entries = books.filter { $0.id != excluded }.map { book in
            Entry(
                bookID: book.id,
                label: Self.label(title: book.title, year: book.year),
                isbn13: book.isbn13,
                titleKey: TextFolding.fold(AuthorName.normalize(book.title)),
                authorKeys: Set(book.orderedAuthors.map { AuthorName.matchKey($0.name) })
            )
        }
    }

    public func match(for draft: BookDraft) -> Entry? {
        let isbn: String?
        if case .valid(let value) = ISBN.parse(draft.isbnText) { isbn = value.isbn13 } else { isbn = nil }
        if let isbn, let hit = entries.first(where: { $0.isbn13 == isbn }) { return hit }
        let title = TextFolding.fold(AuthorName.normalize(draft.title))
        guard !title.isEmpty else { return nil }
        let authors = Set(draft.authors.map { AuthorName.matchKey($0.name) })
        guard !authors.isEmpty else { return nil }
        return entries.first { $0.titleKey == title && !$0.authorKeys.isDisjoint(with: authors) }
    }

    /// "Der Zauberberg (1924)", or the title alone without a year.
    public static func label(title: String, year: Int?) -> String {
        guard let year else { return title }
        return "\(title) (\(String(year)))"
    }
}
