import Testing
@testable import BuchhalterCore

struct ISBNHyphenationTests {
    private func hyphenated(_ text: String) -> String? {
        if case .valid(let isbn) = ISBN.parse(text) { return isbn.hyphenated }
        return nil
    }

    @Test func englishGermanAndFrenchGroups() {
        #expect(hyphenated("9780306406157") == "978-0-306-40615-7")
        #expect(hyphenated("9783150115374") == "978-3-15-011537-4")
        #expect(hyphenated("9783935890595") == "978-3-935890-59-5")
        #expect(hyphenated("9783596294312") == "978-3-596-29431-2")
        #expect(hyphenated("9782070360024") == "978-2-07-036002-4")
    }

    @Test func isbn10AndAnyInputBecomeTheSameISBN13Form() {
        for text in ["0-306-40615-2", "0306406152", "978 0 306 40615 7", "978-030640615-7"] {
            #expect(hyphenated(text) == "978-0-306-40615-7", "\(text)")
        }
    }

    @Test func prefix979() {
        // 979-10 is France.
        #expect(hyphenated("9791032305690") == "979-10-323-0569-0")
    }

    @Test func unknownRangeKeepsThePrefixApart() {
        // 979-0 is not assigned to books.
        let hyphenation = ISBNHyphenation(prefixes: "979 1000000-1599999:2", groups: "")
        #expect(hyphenation.hyphenate("9790123456785") == "979-0123456785")
        #expect(hyphenation.hyphenate("9791012345678") == "979-1012345678")
    }

    @Test func formattedLeavesInvalidTextAlone() {
        #expect(ISBN.formatted("978-3-10-048431-7") == "978-3-10-048431-7")
        #expect(ISBN.formatted("12345") == "12345")
        #expect(ISBN.formatted("") == "")
        #expect(ISBN.formatted(" 315011537X ") == "978-3-15-011537-4")
    }
}
