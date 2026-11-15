import Foundation
import Testing
@testable import BuchhalterCore

struct LookupMatchingTests {
    private func titleQuery(_ title: String, _ author: String) -> LookupQuery {
        .titleAuthor(title: title, authors: [AuthorDraft(name: author, sortName: AuthorName.guessSortName(author))])
    }

    private func buddenbrooks() throws -> [LookupRecord] {
        try MARCXMLParser.parse(fixture("dnb-buddenbrooks-mann.xml")).records.compactMap(DNBRecordMapper.record(from:))
    }

    @Test func buddenbrooksFixtureKeepsTheRealEditions() throws {
        let all = try buddenbrooks()
        let matches = LookupMatching.matches(all, for: titleQuery("Buddenbrooks", "Thomas Mann"))
        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { $0.title.lowercased().contains("buddenbrooks") })
        let dropped = Set(all.map(\.id)).subtracting(matches.map(\.id))
        let droppedTitles = all.filter { dropped.contains($0.id) }.map(\.title)
        for title in ["Meine Buddenbrooks", "Huset Buddenbrook"] {
            #expect(droppedTitles.contains(title), "\(title) should be dropped")
        }
        #expect(droppedTitles.contains { $0.hasPrefix("Huch, alle tot?") })
        #expect(droppedTitles.contains { $0.hasPrefix("Thomas Mann: Buddenbrooks") || $0.hasPrefix("Thomas Mann:") })
        #expect(droppedTitles.contains("Bu deng bu luo ke jia zu"))
        #expect(!matches.contains { $0.title == "Meine Buddenbrooks" })
        // Both title forms count: "The Buddenbrooks" is kept.
        #expect(matches.contains { $0.title == "The Buddenbrooks" })
        #expect(matches.contains { $0.title.hasPrefix("Buddenbrooks") })
    }

    @Test func typedAuthorMatchesWithoutDiacritics() throws {
        let piercing = try MARCXMLParser.parse(fixture("dnb-isbn-piercing.xml")).records.compactMap(DNBRecordMapper.record(from:))
        #expect(LookupMatching.matches(piercing, for: titleQuery("Piercing", "Ryu Murakami")).count == 1)
        #expect(LookupMatching.matches(piercing, for: titleQuery("piercing", "ryū murakami")).count == 1)
        #expect(LookupMatching.matches(piercing, for: titleQuery("Piercing", "Haruki Murakami")).isEmpty)
        #expect(LookupMatching.matches(piercing, for: titleQuery("Pierc", "Ryu Murakami")).count == 1)
        #expect(LookupMatching.matches(piercing, for: titleQuery("Other", "Ryu Murakami")).isEmpty)
    }

    @Test func anyTypedAuthorCounts() {
        let record = makeRecord("Titel", by: ["Mann, Thomas"])
        let query = LookupQuery.titleAuthor(title: "Titel", authors: [
            AuthorDraft(name: "Someone Else", sortName: "Else, Someone"),
            AuthorDraft(name: "Thomas Mann", sortName: "Mann, Thomas"),
        ])
        #expect(LookupMatching.matches([record], for: query).count == 1)
    }

    @Test func isbnQueryIgnoresTitleAndAuthorAndDeduplicates() throws {
        let isbn = try #require({ if case .valid(let v) = ISBN.parse("978-3-935890-59-5") { v } else { nil } }())
        let a = makeRecord("Piercing", by: ["Someone"], isbn: ["9783935890595"], id: "a")
        let b = makeRecord("Piercing again", by: ["Other"], isbn: ["9783935890595"], id: "b")
        let c = makeRecord("Unrelated", isbn: ["9783150115374"], id: "c")
        let matches = LookupMatching.matches([c, a, b], for: .isbn(isbn, display: "978-3-935890-59-5"))
        #expect(matches.map(\.id) == ["a"])
        #expect(LookupMatching.matches([c], for: .isbn(isbn, display: "")).isEmpty)
    }

    @Test func orderPutsThePreferredLanguageFirstThenNewestWithoutYearLast() {
        let records = [
            makeRecord("A", year: 2020, language: "en", id: "en2020"),
            makeRecord("B", year: nil, language: "de", id: "deNil"),
            makeRecord("C", year: 2010, language: "de", id: "de2010"),
            makeRecord("D", year: 2026, language: "de", id: "de2026"),
            makeRecord("E", year: nil, language: "en", id: "enNil"),
            makeRecord("F", year: 2026, language: "fr", id: "fr2026"),
        ]
        let ordered = LookupMatching.ordered(records, preferredLanguage: "de")
        #expect(ordered.map(\.id) == ["de2026", "de2010", "deNil", "fr2026", "en2020", "enNil"])
    }

    @Test func orderWithoutPreferredLanguageIsNewestFirstAndStable() {
        let records = [
            makeRecord("A", year: 2020, id: "first"), makeRecord("B", year: 2020, id: "second"),
            makeRecord("C", year: 2021, id: "third"),
        ]
        #expect(LookupMatching.ordered(records, preferredLanguage: nil).map(\.id) == ["third", "first", "second"])
    }

    @Test func queryFromDraft() throws {
        var draft = BookDraft()
        #expect(LookupQuery(draft: draft) == nil)
        draft.title = "Buddenbrooks"
        #expect(LookupQuery(draft: draft) == nil)
        #expect(LookupQuery(draft: draft, pendingAuthor: "Thomas Mann") != nil)
        draft.authors = [AuthorDraft(name: "Thomas Mann", sortName: "Mann, Thomas")]
        if case .titleAuthor(let title, let authors)? = LookupQuery(draft: draft) {
            #expect(title == "Buddenbrooks" && authors.count == 1)
        } else {
            Issue.record("expected a title-and-author query")
        }
        // A valid ISBN wins; an invalid one is ignored.
        draft.isbnText = "978-3-935890-59-5"
        if case .isbn(let isbn, let display)? = LookupQuery(draft: draft) {
            #expect(isbn.isbn13 == "9783935890595" && display == "978-3-935890-59-5")
        } else {
            Issue.record("expected an ISBN query")
        }
        draft.isbnText = "978-3-935890-59-4"
        if case .titleAuthor? = LookupQuery(draft: draft) {} else { Issue.record("invalid ISBN must be ignored") }
        var onlyISBN = BookDraft()
        onlyISBN.isbnText = "3935890591"
        #expect(LookupQuery(draft: onlyISBN) != nil)
    }
}
