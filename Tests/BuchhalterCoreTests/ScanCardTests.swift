import Foundation
import Testing
@testable import BuchhalterCore

struct ScanCardTests {
    private var isbn: ISBN {
        guard case .valid(let isbn) = ISBN.parse("978-3-596-29431-2") else { fatalError("test ISBN") }
        return isbn
    }
    private func record(_ id: String, year: Int) -> LookupRecord {
        LookupRecord(id: id, source: .dnb, title: "Buddenbrooks", year: year, isbn13s: ["9783596294312"])
    }

    @Test func looksUpWhileTheSourcesAreAsked() {
        var card = ScanCard(isbn: isbn, firstSource: .dnb)
        #expect(card.phase == .looking(.dnb))
        #expect(!card.canAdd)
        card.asking(.openLibrary)
        #expect(card.phase == .looking(.openLibrary))
    }

    @Test func aSingleMatchHasNoOtherEditions() {
        var card = ScanCard(isbn: isbn, firstSource: .dnb)
        card.finished(.single(record("dnb:1", year: 1989)))
        #expect(card.phase == .found)
        #expect(card.record?.id == "dnb:1")
        #expect(card.otherEditionCount == 0)
        #expect(card.canAdd)
    }

    @Test func severalMatchesShowTheFirstAndCountTheOthers() {
        var card = ScanCard(isbn: isbn, firstSource: .dnb)
        let list = EditionList(
            source: .dnb, records: [record("dnb:3", year: 2009), record("dnb:2", year: 1999), record("dnb:1", year: 1989)],
            totalCount: 3
        )
        card.finished(.several(list))
        #expect(card.record?.id == "dnb:3")
        #expect(card.otherEditionCount == 2)
        card.choose(record("dnb:1", year: 1989))
        #expect(card.record?.id == "dnb:1")
        #expect(card.otherEditionCount == 2)
        // A record that is not one of the editions changes nothing.
        card.choose(record("other", year: 2000))
        #expect(card.record?.id == "dnb:1")
    }

    @Test func noMatchAndNoSource() {
        var card = ScanCard(isbn: isbn, firstSource: .dnb)
        card.finished(.none)
        #expect(card.phase == .notFound)
        #expect(!card.canAdd)
        card.failedEverywhere()
        #expect(card.phase == .unreachable)
        card.retry(firstSource: .openLibrary)
        #expect(card.phase == .looking(.openLibrary))
        #expect(card.record == nil)
    }
}
