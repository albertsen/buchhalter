import Foundation

/// Every sentence the lookup shows. A sentence that names a source is one
/// catalog key per source, chosen by a `switch`, never an interpolated name:
/// German inflects it ("aus der Deutschen Nationalbibliothek"), and every key
/// is a literal at its call site so `make strings` finds it. The locale is
/// explicit so tests can check both languages; in the test runner (no
/// catalog) the values are the English keys.
public struct LookupMessages: Sendable {
    public var locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    // MARK: Running

    /// "Searching the Deutsche Nationalbibliothek for “Buddenbrooks” by Thomas Mann…".
    public func searching(_ query: LookupQuery, source: LookupSource) -> String {
        switch (query, source) {
        case let (.titleAuthor(title, authors), .dnb):
            return String(localized: "Searching the Deutsche Nationalbibliothek for “\(title)” by \(names(authors))…", locale: locale)
        case let (.titleAuthor(title, authors), .openLibrary):
            return String(localized: "Searching Open Library for “\(title)” by \(names(authors))…", locale: locale)
        case let (.isbn(_, display), .dnb):
            return String(localized: "Searching the Deutsche Nationalbibliothek for ISBN \(display)…", locale: locale)
        case let (.isbn(_, display), .openLibrary):
            return String(localized: "Searching Open Library for ISBN \(display)…", locale: locale)
        case let (.titleAuthor(title, authors), .googleBooks):
            return String(localized: "Searching Google Books for “\(title)” by \(names(authors))…", locale: locale)
        case let (.isbn(_, display), .googleBooks):
            return String(localized: "Searching Google Books for ISBN \(display)…", locale: locale)
        }
    }

    // MARK: Hints

    public func noMatch(_ query: LookupQuery) -> String {
        switch query {
        case let .titleAuthor(title, authors):
            String(localized: "No book found for “\(title)” by \(names(authors)). Check the spelling, or enter the ISBN and try again.", locale: locale)
        case let .isbn(_, display):
            String(localized: "No book found for ISBN \(display). Check the number, or enter the title and author instead.", locale: locale)
        }
    }

    /// The red hint after every source asked has failed. One source asked: it
    /// is named, as before. Several: "any book source".
    public func unreachable(_ sources: [LookupSource]) -> String {
        guard sources.count == 1, let source = sources.first else {
            return String(localized: "Can't reach any book source. Check the internet connection. You can still add the book by hand.", locale: locale)
        }
        switch source {
        case .dnb:
            return String(localized: "Can't reach the Deutsche Nationalbibliothek. Check the internet connection. You can still add the book by hand.", locale: locale)
        case .openLibrary:
            return String(localized: "Can't reach Open Library. Check the internet connection. You can still add the book by hand.", locale: locale)
        case .googleBooks:
            return String(localized: "Can't reach Google Books. Check the internet connection. You can still add the book by hand.", locale: locale)
        }
    }

    /// The message of Find Cover's "No cover found" alert. When Google Books
    /// is off or has no key, it says that Google Books often has one.
    public func noCoverMessage(suggestingGoogleBooks: Bool) -> String {
        if suggestingGoogleBooks {
            String(localized: "None of the sources that are on has a cover for this book. Google Books often has one: add a key and turn it on in Settings.", locale: locale)
        } else {
            String(localized: "None of the sources that are on has a cover for this book.", locale: locale)
        }
    }

    /// The message of Find Synopsis's "No synopsis found" alert.
    public func noSynopsisMessage(suggestingGoogleBooks: Bool) -> String {
        if suggestingGoogleBooks {
            String(localized: "None of your book sources has a synopsis for this book. Google Books often has one: add a key and turn it on in Settings.", locale: locale)
        } else {
            String(localized: "None of your book sources has a synopsis for this book.", locale: locale)
        }
    }

    // MARK: Synopsis

    /// The grey line under a synopsis: "From the Deutsche Nationalbibliothek".
    public func synopsisFrom(_ source: LookupSource) -> String {
        switch source {
        case .dnb: String(localized: "From the Deutsche Nationalbibliothek", locale: locale)
        case .openLibrary: String(localized: "From Open Library", locale: locale)
        case .googleBooks: String(localized: "From Google Books", locale: locale)
        }
    }

    /// The offer in the Synopsis tab when the source's text differs from the book's.
    public func differentSynopsis(_ source: LookupSource) -> String {
        switch source {
        case .dnb: String(localized: "The Deutsche Nationalbibliothek has a different synopsis", locale: locale)
        case .openLibrary: String(localized: "Open Library has a different synopsis", locale: locale)
        case .googleBooks: String(localized: "Google Books has a different synopsis", locale: locale)
        }
    }

    // MARK: Banner

    /// The green banner after filling. The counts use the catalog's plural rules.
    public func banner(_ result: LookupResult) -> String {
        let filled = result.filledCount
        let differ = result.differCount
        switch (result.source, filled > 0, differ > 0) {
        case (.dnb, true, false):
            return String(localized: "Filled in \(filled) fields from the Deutsche Nationalbibliothek. Check them, then add the book.", locale: locale)
        case (.openLibrary, true, false):
            return String(localized: "Filled in \(filled) fields from Open Library. Check them, then add the book.", locale: locale)
        case (.dnb, true, true):
            return String(localized: "Filled in \(filled) empty fields from the Deutsche Nationalbibliothek. \(differ) values differ and stay until you use them.", locale: locale)
        case (.openLibrary, true, true):
            return String(localized: "Filled in \(filled) empty fields from Open Library. \(differ) values differ and stay until you use them.", locale: locale)
        case (.dnb, false, true):
            return String(localized: "No empty fields to fill. \(differ) values differ from the Deutsche Nationalbibliothek and stay until you use them.", locale: locale)
        case (.openLibrary, false, true):
            return String(localized: "No empty fields to fill. \(differ) values differ from Open Library and stay until you use them.", locale: locale)
        case (.dnb, false, false):
            return String(localized: "Nothing to fill in. Everything matches the Deutsche Nationalbibliothek.", locale: locale)
        case (.openLibrary, false, false):
            return String(localized: "Nothing to fill in. Everything matches Open Library.", locale: locale)
        case (.googleBooks, true, false):
            return String(localized: "Filled in \(filled) fields from Google Books. Check them, then add the book.", locale: locale)
        case (.googleBooks, true, true):
            return String(localized: "Filled in \(filled) empty fields from Google Books. \(differ) values differ and stay until you use them.", locale: locale)
        case (.googleBooks, false, true):
            return String(localized: "No empty fields to fill. \(differ) values differ from Google Books and stay until you use them.", locale: locale)
        case (.googleBooks, false, false):
            return String(localized: "Nothing to fill in. Everything matches Google Books.", locale: locale)
        }
    }

    // MARK: Edition list

    /// "12 books match “Buddenbrooks” by Thomas Mann. Newest first."
    public func editionsHeadline(count: Int, query: LookupQuery) -> String {
        switch query {
        case let .titleAuthor(title, authors):
            String(localized: "\(count) books match “\(title)” by \(names(authors)). Newest first.", locale: locale)
        case let .isbn(_, display):
            String(localized: "\(count) books match ISBN \(display). Newest first.", locale: locale)
        }
    }

    public func truncatedNote() -> String {
        String(localized: "Only the 100 newest records were searched. Enter the ISBN to find a specific edition.", locale: locale)
    }

    // MARK: Notes next to fields

    /// "DNB: 2009" / "Open Library: 2009" / "Google Books: 2009". The sheet adds the Use button.
    public func offerLabel(source: LookupSource, value: String) -> String {
        switch source {
        case .dnb: String(localized: "DNB: \(value)", locale: locale)
        case .openLibrary: String(localized: "Open Library: \(value)", locale: locale)
        case .googleBooks: String(localized: "Google Books: \(value)", locale: locale)
        }
    }

    public func coverOffer(source: LookupSource) -> String {
        switch source {
        case .dnb: String(localized: "Use DNB cover", locale: locale)
        case .openLibrary: String(localized: "Use Open Library cover", locale: locale)
        case .googleBooks: String(localized: "Use Google Books cover", locale: locale)
        }
    }

    // MARK: Helpers

    private func names(_ authors: [AuthorDraft]) -> String {
        authors.map(\.name).formatted(.list(type: .and).locale(locale))
    }
}
