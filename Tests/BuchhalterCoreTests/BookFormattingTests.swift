import Foundation
import Testing
@testable import BuchhalterCore

@MainActor
struct BookFormattingTests {
    private let en = BookFormatting(locale: Locale(identifier: "en_GB"), timeZone: .current)
    private let de = BookFormatting(locale: Locale(identifier: "de_DE"), timeZone: .current)

    @Test func dayFormat() {
        #expect(en.day(date(2026, 10, 3)) == "3 Oct 2026")
        #expect(de.day(date(2026, 10, 3)) == "3. Okt. 2026")
    }

    /// ICU puts thin or non-breaking spaces around the dash; compare with plain spaces.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2009}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    @Test func rangeFormat() {
        #expect(plain(en.range(date(2019, 1, 12), date(2019, 3, 2))) == "12 Jan – 2 Mar 2019")
        #expect(plain(de.range(date(2019, 1, 12), date(2019, 3, 2))) == "12. Jan. – 2. März 2019")
    }

    @Test func yearHasNoGrouping() {
        #expect(en.year(1901) == "1901")
        #expect(de.year(1901) == "1901")
    }

    @Test func languageNames() {
        #expect(en.languageName("de") == "German")
        #expect(de.languageName("de") == "Deutsch")
    }

    @Test func metaLineNamesTheOriginalLanguage() throws {
        let t = try TestLibrary()
        var draft = BookDraft()
        draft.title = "Piercing"
        draft.yearText = "1994"
        draft.language = "de"
        draft.originalLanguage = "ja"
        let book = try t.library.addBook(draft)
        #expect(en.metaLine(book).hasPrefix("1994 · "))
        #expect(en.metaLine(book).hasSuffix("German (original: Japanese)"))
        book.language = nil
        #expect(en.metaLine(book).hasSuffix("Original: Japanese"))
        book.language = "de"
        book.originalLanguage = nil
        #expect(en.metaLine(book).hasSuffix("German"))
    }

    @Test func sentencesFallBackToEnglishInTests() throws {
        let t = try TestLibrary()
        let book = try t.add("Buddenbrooks", status: .reading, started: date(2026, 10, 3))
        let reading = try #require(book.currentReading)
        #expect(en.statusLine(reading) == "Started 3 Oct 2026")
        #expect(en.badge(reading) == "Reading since 3 Oct 2026")
        #expect(en.readingSummary(reading) == "Started 3 Oct 2026")
        try t.library.finishReading(book, on: date(2026, 11, 1), rating: nil, notes: nil)
        #expect(en.statusLine(reading) == "Finished 1 Nov 2026")
        #expect(plain(en.readingSummary(reading)) == "3 Oct – 1 Nov 2026")
        #expect(en.sortButtonLabel(.default) == "Sort: Author, Year")
    }

    // MARK: Lookup rows

    private var edition: LookupRecord {
        LookupRecord(
            id: "dnb:1", source: .dnb, title: "Buddenbrooks",
            authors: [LookupAuthor(name: "Thomas Mann")], year: 2026, pages: 781, language: "de",
            publisher: "Reclam", isbn13s: ["9783150115374"], isbnDisplay: "978-3-15-011537-4"
        )
    }

    @Test func editionLines() {
        #expect(en.editionByline(edition) == "Thomas Mann · Reclam · 2026")
        #expect(en.editionDetails(edition) == "781 pages · German · ISBN 978-3-15-011537-4")
        #expect(de.editionByline(edition) == "Thomas Mann · Reclam · 2026")
        var sparse = edition
        sparse.authors = []
        sparse.publisher = nil
        sparse.pages = nil
        sparse.isbnDisplay = nil
        #expect(en.editionByline(sparse) == "2026")
        #expect(en.editionDetails(sparse) == "German")
        sparse.authors = [LookupAuthor(name: "A"), LookupAuthor(name: "B")]
        #expect(en.editionByline(sparse) == "A and B · 2026")
    }
}
