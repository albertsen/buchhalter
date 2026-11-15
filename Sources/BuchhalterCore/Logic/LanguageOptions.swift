import Foundation

/// The languages offered in the Language popup. Codes already used in the
/// library come first, then all two-letter ISO 639 codes sorted by their name
/// in the current locale. Nothing extra is stored.
public enum LanguageOptions {
    public static func codes(used: [String], locale: Locale = .current) -> (used: [String], others: [String]) {
        var seen = Set<String>()
        let usedCodes = used.filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { name($0, locale) < name($1, locale) }
        let all = Locale.LanguageCode.isoLanguageCodes.map(\.identifier).filter { $0.count == 2 }
        let others = all.filter { !seen.contains($0) && locale.localizedString(forLanguageCode: $0) != nil }
            .sorted { TextFolding.compare(name($0, locale), name($1, locale)) == .orderedAscending }
        return (usedCodes, others)
    }

    public static func name(_ code: String, _ locale: Locale = .current) -> String {
        locale.localizedString(forLanguageCode: code) ?? code
    }

    /// The language of the most recently added book, or nil in an empty library.
    @MainActor
    public static func defaultLanguage(books: [Book]) -> String? {
        books.filter { $0.language != nil }.max { $0.addedAt < $1.addedAt }?.language
    }
}
