import Testing
@testable import BuchhalterCore

struct BarcodeReadingTests {
    @Test func a978BarcodeIsAnISBN() {
        guard case .isbn(let isbn) = BarcodeReading.classify("9783596294312") else {
            Issue.record("expected an ISBN")
            return
        }
        #expect(isbn.isbn13 == "9783596294312")
        #expect(isbn.hyphenated == "978-3-596-29431-2")
    }

    @Test func a979BarcodeIsAnISBN() {
        guard case .isbn(let isbn) = BarcodeReading.classify("9791090636071") else {
            Issue.record("expected an ISBN")
            return
        }
        #expect(isbn.isbn13 == "9791090636071")
    }

    @Test func otherEAN13IsNotAnISBN() {
        #expect(BarcodeReading.classify("4006381333931") == .notISBN(display: "4 006381 333931"))
        // 977 is the prefix of magazines (ISSN), 978-less but still a valid EAN-13.
        #expect(BarcodeReading.classify("9771234567003") == .notISBN(display: "9 771234 567003"))
    }

    @Test func aWrongCheckDigitIsIgnored() {
        #expect(BarcodeReading.classify("9783596294313") == .ignored)
        #expect(BarcodeReading.classify("4006381333932") == .ignored)
    }

    @Test func otherLengthsAndLettersAreIgnored() {
        // A 12-digit UPC-A, an ISBN-10 (valid for ISBN.parse, not here), letters, an add-on, nothing.
        #expect(BarcodeReading.classify("036000291452") == .ignored)
        #expect(BarcodeReading.classify("3596294312") == .ignored)
        #expect(BarcodeReading.classify("978359629431X") == .ignored)
        #expect(BarcodeReading.classify("97835962943125") == .ignored)
        #expect(BarcodeReading.classify("") == .ignored)
        #expect(BarcodeReading.classify("978-3-596-29431-2") == .ignored)
    }
}
