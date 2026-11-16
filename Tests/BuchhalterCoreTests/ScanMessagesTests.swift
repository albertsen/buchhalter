import Foundation
import Testing
@testable import BuchhalterCore

@MainActor
struct ScanMessagesTests {
    private let messages = ScanMessages(locale: Locale(identifier: "en"))

    @Test func theTextsFillTheirPlaceholders() throws {
        guard case .valid(let isbn) = ISBN.parse("9783596294312") else {
            Issue.record("test ISBN")
            return
        }
        #expect(messages.isbnRead(isbn) == "ISBN 978-3-596-29431-2")
        #expect(messages.notISBN(display: "4 006381 333931")
            == "This barcode isn't an ISBN (4 006381 333931). Look for the one that starts with 978 or 979.")
        #expect(messages.looking() == "Looking for a barcode…")

        let t = try TestLibrary()
        try t.add("Buddenbrooks", year: 1901, isbn: "9783596294312")
        let entry = try #require(DuplicateIndex(books: t.library.fetchBooks()).match(isbn13: "9783596294312"))
        #expect(messages.alreadyInLibrary(entry) == "Already in your library: Buddenbrooks (1901)")
    }
}
