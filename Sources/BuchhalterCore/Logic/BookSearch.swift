import Foundation

/// What one book can be found by, folded once per book.
public struct SearchKey: Sendable {
    let haystack: String
    let isbnDigits: String

    public init(
        title: String, subtitle: String?, authors: [String], publisher: String?,
        isbnText: String?, isbn13: String?, notes: [String]
    ) {
        let parts = [title, subtitle ?? "", publisher ?? "", isbnText ?? "", isbn13 ?? ""] + authors + notes
        haystack = TextFolding.fold(parts.joined(separator: "\n"))
        isbnDigits = ((isbnText ?? "") + (isbn13 ?? "")).filter { $0 != "-" && !$0.isWhitespace }
    }

    @MainActor
    public init(book: Book) {
        self.init(
            title: book.title, subtitle: book.subtitle,
            authors: book.orderedAuthors.map(\.name),
            publisher: book.publisher, isbnText: book.isbnText, isbn13: book.isbn13,
            notes: (book.readings ?? []).compactMap(\.notes)
        )
    }
}

public enum BookSearch {
    /// Every whitespace-separated token must appear. "boll" matches "Böll".
    public static func matches(_ key: SearchKey, query: String) -> Bool {
        let tokens = TextFolding.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { token in
            if key.haystack.contains(token) { return true }
            let digits = token.filter { $0 != "-" }
            return !digits.isEmpty && digits.contains(where: \.isNumber) && key.isbnDigits.contains(digits)
        }
    }

    @MainActor
    public static func filter(_ books: [Book], query: String) -> [Book] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return books }
        return books.filter { matches(SearchKey(book: $0), query: trimmed) }
    }
}
