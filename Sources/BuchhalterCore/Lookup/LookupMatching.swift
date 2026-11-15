import Foundation

/// Decides which of a service's records are real matches for what the user
/// typed, and in which order the edition list shows them. Both services
/// return loose results ("Meine Buddenbrooks", study guides, a book by
/// another Mann), so the app checks them itself.
public enum LookupMatching {
    // MARK: Matches

    /// - Title and author: a record matches when a title form starts with the
    ///   typed title and one typed author is one of the record's authors.
    ///   Comparison is case- and diacritic-insensitive.
    /// - ISBN: records that carry the ISBN, deduplicated by it, first kept.
    public static func matches(_ records: [LookupRecord], for query: LookupQuery) -> [LookupRecord] {
        switch query {
        case .isbn(let isbn, _):
            guard let first = records.first(where: { $0.isbn13s.contains(isbn.isbn13) }) else { return [] }
            return [first]
        case .titleAuthor(let title, let authors):
            let typedTitle = TextFolding.fold(AuthorName.normalize(title))
            let typedAuthors = Set(authors.map { AuthorName.matchKey($0.name) })
            guard !typedTitle.isEmpty, !typedAuthors.isEmpty else { return [] }
            return records.filter { record in
                record.titleMatchKeys.contains { $0.hasPrefix(typedTitle) }
                    && record.authors.contains { typedAuthors.contains(AuthorName.matchKey($0.name)) }
            }
        }
    }

    // MARK: Order

    /// Records in the draft's language first, then the rest. Each group is
    /// newest first, records without a year last; the service's order breaks ties.
    public static func ordered(_ records: [LookupRecord], preferredLanguage: String?) -> [LookupRecord] {
        let indexed = Array(records.enumerated())
        func rank(_ record: LookupRecord) -> Int {
            guard let preferredLanguage, record.language == preferredLanguage else { return 1 }
            return 0
        }
        return indexed.sorted { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            if ra != rb { return ra < rb }
            switch (a.element.year, b.element.year) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    // MARK: Author headings

    /// "Mann, Thomas,, 1875-1955" and "Mann, Thomas, (1875-1955)" give
    /// "Thomas Mann" sorted as "Mann, Thomas". A heading without a comma
    /// ("Man en", "John Williams") stays as it is, with no sort name.
    public static func headingToName(_ heading: String) -> LookupAuthor {
        let parts = heading.split(separator: ",", omittingEmptySubsequences: true)
            .map { AuthorName.normalize(String($0)) }
            .filter { part in
                !part.isEmpty && !part.contains(where: { $0.isNumber || $0 == "(" || $0 == ")" })
            }
        let kept = Array(parts.prefix(2))
        guard kept.count == 2 else {
            return LookupAuthor(name: kept.first ?? AuthorName.normalize(heading))
        }
        return LookupAuthor(name: "\(kept[1]) \(kept[0])", sortName: "\(kept[0]), \(kept[1])")
    }

    /// The first four-digit run between 1000 and 2999 in a date text
    /// ("[2026]", "©2026", "Sep 23, 2014", "2025.05").
    static func year(in text: String) -> Int? {
        var digits = ""
        for character in text + " " {
            if character.isASCII, character.isNumber {
                digits.append(character)
                continue
            }
            if digits.count == 4, let value = Int(digits), (1000...2999).contains(value) { return value }
            digits = ""
        }
        return nil
    }
}
