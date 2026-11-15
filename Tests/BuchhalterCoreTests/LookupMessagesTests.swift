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

    @Test func unreachableNamesTheFailedSource() {
        #expect(messages.unreachable(.dnb).contains("Deutsche Nationalbibliothek"))
        #expect(messages.unreachable(.openLibrary).contains("Open Library"))
        #expect(!messages.unreachable(.openLibrary).contains("Deutsche"))
    }

    @Test func offerLabelsAndCoverOffers() {
        #expect(messages.offerLabel(source: .dnb, value: "2009") == "DNB: 2009")
        #expect(messages.offerLabel(source: .openLibrary, value: "2009") == "Open Library: 2009")
        #expect(messages.coverOffer(source: .dnb) == "Use DNB cover")
        #expect(messages.coverOffer(source: .openLibrary) == "Use Open Library cover")
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
    }
}
