import Foundation
import Testing
@testable import BuchhalterCore

/// In the test runner there is no catalog, so every text is its English key.
struct LookupMessagesTests {
    private let messages = LookupMessages(locale: Locale(identifier: "en"))

    private let titleQuery = LookupQuery.titleAuthor(
        title: "Buddenbrooks", authors: [AuthorDraft(name: "Thomas Mann", sortName: "Mann, Thomas")]
    )

    private var isbnQuery: LookupQuery {
        if case .valid(let isbn) = ISBN.parse("978-3-15-011537-4") { .isbn(isbn, display: "978-3-15-011537-4") } else { fatalError("bad ISBN") }
    }

    @Test func searchingNamesTheSourceAndTheQuery() {
        #expect(messages.searching(titleQuery, source: .dnb)
            == "Searching the Deutsche Nationalbibliothek for “Buddenbrooks” by Thomas Mann…")
        #expect(messages.searching(titleQuery, source: .openLibrary) == "Searching Open Library for “Buddenbrooks” by Thomas Mann…")
        #expect(messages.searching(isbnQuery, source: .dnb) == "Searching the Deutsche Nationalbibliothek for ISBN 978-3-15-011537-4…")
        #expect(messages.searching(isbnQuery, source: .openLibrary) == "Searching Open Library for ISBN 978-3-15-011537-4…")
        #expect(messages.searching(titleQuery, source: .googleBooks) == "Searching Google Books for “Buddenbrooks” by Thomas Mann…")
        #expect(messages.searching(isbnQuery, source: .googleBooks) == "Searching Google Books for ISBN 978-3-15-011537-4…")
    }

    @Test func severalAuthorsFormatAsAList() {
        let query = LookupQuery.titleAuthor(title: "T", authors: [
            AuthorDraft(name: "A One", sortName: "One, A"), AuthorDraft(name: "B Two", sortName: "Two, B"),
        ])
        #expect(messages.noMatch(query).contains("A One and B Two"))
    }

    @Test func noMatchHints() {
        #expect(messages.noMatch(titleQuery)
            == "No book found for “Buddenbrooks” by Thomas Mann. Check the spelling, or enter the ISBN and try again.")
        #expect(messages.noMatch(isbnQuery)
            == "No book found for ISBN 978-3-15-011537-4. Check the number, or enter the title and author instead.")
    }

    @Test func unreachableNamesTheOneSourceAskedOrAnyOfSeveral() {
        #expect(messages.unreachable([.dnb]).contains("Deutsche Nationalbibliothek"))
        #expect(messages.unreachable([.openLibrary]).contains("Open Library"))
        #expect(!messages.unreachable([.openLibrary]).contains("Deutsche"))
        #expect(messages.unreachable([.googleBooks])
            == "Can't reach Google Books. Check the internet connection. You can still add the book by hand.")
        #expect(messages.unreachable([.dnb, .openLibrary])
            == "Can't reach any book source. Check the internet connection. You can still add the book by hand.")
        #expect(messages.unreachable([.googleBooks, .dnb, .openLibrary]).contains("any book source"))
    }

    @Test func noCoverMessageSuggestsGoogleBooksOnlyWhenAsked() {
        #expect(messages.noCoverMessage(suggestingGoogleBooks: false)
            == "None of the sources that are on has a cover for this book.")
        #expect(messages.noCoverMessage(suggestingGoogleBooks: true)
            == "None of the sources that are on has a cover for this book. Google Books often has one: add a key and turn it on in Settings.")
    }

    @Test func offerLabelsAndCoverOffers() {
        #expect(messages.offerLabel(source: .dnb, value: "2009") == "DNB: 2009")
        #expect(messages.offerLabel(source: .openLibrary, value: "2009") == "Open Library: 2009")
        #expect(messages.offerLabel(source: .googleBooks, value: "2009") == "Google Books: 2009")
        #expect(messages.coverOffer(source: .dnb) == "Use DNB cover")
        #expect(messages.coverOffer(source: .openLibrary) == "Use Open Library cover")
        #expect(messages.coverOffer(source: .googleBooks) == "Use Google Books cover")
    }

    @Test func editionsHeadline() {
        #expect(messages.editionsHeadline(count: 12, query: titleQuery) == "12 books match “Buddenbrooks” by Thomas Mann. Newest first.")
    }

    /// The banner picks its sentence by what happened and where it came from.
    @Test func bannerSentencePerStateAndSource() throws {
        let record = makeRecord("Piercing", by: ["Ryu Murakami"], year: 2009)
        let authors = [AuthorDraft(name: "Ryu Murakami", sortName: "Murakami, Ryu")]
        let locale = Locale(identifier: "en")

        // Filled only: an empty draft.
        let (_, filledOnly) = LookupResult.merge(record, authors: authors, cover: nil, into: BookDraft(), locale: locale)
        #expect(messages.banner(filledOnly).hasPrefix("Filled in \(filledOnly.filledCount) fields from the Deutsche Nationalbibliothek. Check them"))

        // Filled and differing.
        var both = BookDraft()
        both.title = "Piercing"
        both.authors = authors
        both.yearText = "1994"
        let (_, mixed) = LookupResult.merge(record, authors: authors, cover: nil, into: both, locale: locale)
        #expect(mixed.differCount == 1 && mixed.filledCount > 0)
        #expect(messages.banner(mixed).contains("empty fields from the Deutsche Nationalbibliothek. 1 values differ"))

        // Differing only.
        var full = BookDraft()
        full.title = "Piercing"
        full.authors = authors
        full.yearText = "1994"
        full.language = "de"
        let openLibrary = LookupRecord(id: "openlibrary:x", source: .openLibrary, title: "Piercing", authors: record.authors, year: 2009, language: "de")
        let (_, differOnly) = LookupResult.merge(openLibrary, authors: authors, cover: nil, into: full, locale: locale)
        #expect(differOnly.filledCount == 0 && differOnly.differCount == 1)
        #expect(messages.banner(differOnly) == "No empty fields to fill. 1 values differ from Open Library and stay until you use them.")

        // Nothing at all.
        full.yearText = "2009"
        let (_, nothing) = LookupResult.merge(openLibrary, authors: authors, cover: nil, into: full, locale: locale)
        #expect(nothing.filledCount == 0 && nothing.differCount == 0)
        #expect(messages.banner(nothing) == "Nothing to fill in. Everything matches Open Library.")
        let (_, dnbNothing) = LookupResult.merge(
            LookupRecord(id: "dnb:1", source: .dnb, title: "Piercing", authors: openLibrary.authors, year: 2009, language: "de"),
            authors: authors, cover: nil, into: full, locale: locale
        )
        #expect(messages.banner(dnbNothing) == "Nothing to fill in. Everything matches the Deutsche Nationalbibliothek.")

        // Google Books: all four sentences name it without an article.
        let google = LookupRecord(id: "googlebooks:x", source: .googleBooks, title: "Piercing", authors: record.authors, year: 2009, language: "de")
        let (_, googleNothing) = LookupResult.merge(google, authors: authors, cover: nil, into: full, locale: locale)
        #expect(messages.banner(googleNothing) == "Nothing to fill in. Everything matches Google Books.")
        full.yearText = "1994"
        let (_, googleDiffer) = LookupResult.merge(google, authors: authors, cover: nil, into: full, locale: locale)
        #expect(messages.banner(googleDiffer) == "No empty fields to fill. 1 values differ from Google Books and stay until you use them.")
        let (_, googleFilled) = LookupResult.merge(google, authors: authors, cover: nil, into: BookDraft(), locale: locale)
        #expect(messages.banner(googleFilled).hasPrefix("Filled in \(googleFilled.filledCount) fields from Google Books. Check them"))
        var googleMixed = both
        googleMixed.yearText = "1994"
        let (_, googleBoth) = LookupResult.merge(google, authors: authors, cover: nil, into: googleMixed, locale: locale)
        #expect(googleBoth.filledCount > 0 && googleBoth.differCount == 1)
        #expect(messages.banner(googleBoth).contains("empty fields from Google Books. 1 values differ"))
    }
}
