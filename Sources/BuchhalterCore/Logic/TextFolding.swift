import Foundation

/// Case- and diacritic-insensitive comparison with German collation, whatever
/// the UI language: "Ä" sorts with "A", "boll" finds "Böll".
public enum TextFolding {
    static let locale = Locale(identifier: "de_DE")
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .numeric]

    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    }

    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: options, range: nil, locale: locale)
    }

    private static let articles: Set<String> = ["der", "die", "das", "the", "a", "an"]

    /// The title without one leading article, when more words follow.
    public static func titleSortKey(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count > 1, articles.contains(words[0].lowercased()) else { return trimmed }
        return words.dropFirst().joined(separator: " ")
    }
}
