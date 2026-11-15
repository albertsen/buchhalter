import Testing
@testable import BuchhalterCore

struct ISBNTests {
    @Test func validISBN13WithAndWithoutSeparators() {
        for text in ["978-3-596-29431-2", "9783596294312", "978 3 596 29431 2"] {
            #expect(ISBN.parse(text) == .valid(ISBN(isbn13: "9783596294312")), "\(text)")
        }
    }

    @Test func validISBN10IncludingX() {
        #expect(ISBN.parse("0-8044-2957-X") == .valid(ISBN(isbn13: "9780804429573")))
        #expect(ISBN.parse("080442957x") == .valid(ISBN(isbn13: "9780804429573")))
        #expect(ISBN.parse("0 8044 2957 X") == .valid(ISBN(isbn13: "9780804429573")))
    }

    @Test func isbn10ConvertsToISBN13() {
        #expect(ISBN.parse("3-596-29431-2") == .valid(ISBN(isbn13: "9783596294312")))
        #expect(ISBN.parse("3596294312") == ISBN.parse("978-3-596-29431-2"))
    }

    @Test func wrongCheckDigitIsInvalid() {
        #expect(ISBN.parse("978-3-10-048431-7") == .invalid)
        #expect(ISBN.parse("978-3-596-29431-3") == .invalid)
        #expect(ISBN.parse("3596294316") == .invalid)
    }

    @Test func shortInputIsIncompleteAndEmptyIsEmpty() {
        #expect(ISBN.parse("") == .empty)
        #expect(ISBN.parse("  - ") == .empty)
        #expect(ISBN.parse("978-3") == .incomplete)
        #expect(ISBN.parse("97835962943") == .incomplete)
    }

    @Test func nonDigitsAreInvalidAtFullLength() {
        #expect(ISBN.parse("97835962943AB") == .invalid)
        #expect(ISBN.parse("1234567890123456") == .invalid)
        #expect(ISBN.parse("9783596294312") != .invalid)
    }

    @Test func thirteenDigitsNeedAPrefix() {
        #expect(ISBN.parse("1234567890128") == .invalid)
    }
}
