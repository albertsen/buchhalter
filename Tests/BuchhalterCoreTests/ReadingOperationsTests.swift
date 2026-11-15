import Foundation
import Testing
@testable import BuchhalterCore

@MainActor
struct ReadingOperationsTests {
    @Test func finishNeedsOnlyADate() throws {
        let t = try TestLibrary()
        let book = try t.add("A", status: .reading, started: date(2026, 10, 3))
        try t.library.finishReading(book, on: date(2026, 11, 1), rating: nil, notes: nil)
        #expect(book.status == .finished)
        #expect(book.currentReading?.endedAt == date(2026, 11, 1))
        #expect(book.currentReading?.stars == nil)
    }

    @Test func finishRefusesBeforeStartAndWrongState() throws {
        let t = try TestLibrary()
        let book = try t.add("A", status: .reading, started: date(2026, 10, 3))
        #expect(throws: LibraryError.self) {
            try t.library.finishReading(book, on: date(2026, 10, 1), rating: nil, notes: nil)
        }
        #expect(throws: LibraryError.self) {
            try t.library.finishReading(book, on: date(2026, 10, 5), rating: 9, notes: nil)
        }
        #expect(book.status == .reading)
        let want = try t.add("B", status: .wantToRead)
        #expect(throws: LibraryError.self) {
            try t.library.finishReading(want, on: date(2026, 10, 5), rating: nil, notes: nil)
        }
    }

    @Test func abandonWithAndWithoutADate() throws {
        let t = try TestLibrary()
        let a = try t.add("A", status: .reading, started: date(2026, 10, 3))
        let b = try t.add("B", status: .reading, started: date(2026, 10, 3))
        try t.library.abandonReading(a, on: date(2026, 11, 5), notes: "Boring")
        try t.library.abandonReading(b, on: nil, notes: nil)
        #expect(a.status == .abandoned && a.currentReading?.endedAt == date(2026, 11, 5))
        #expect(a.currentReading?.notes == "Boring")
        #expect(b.status == .abandoned && b.currentReading?.endedAt == nil)
    }

    @Test func readAgainCreatesASecondReadingNotASecondBook() throws {
        let t = try TestLibrary()
        let book = try t.add("A", status: .read, started: date(2019, 1, 12), finished: date(2019, 3, 2))
        #expect(throws: Never.self) { try t.library.readAgain(book) }
        #expect(book.status == .reading)
        #expect(book.readings?.count == 2)
        #expect(t.library.fetchBooks().count == 1)
        #expect(book.readingsNewestFirst.map(\.status) == [.reading, .finished])
        #expect(throws: LibraryError.self) { try t.library.readAgain(book) }
    }

    @Test func applyStatusRules() throws {
        let t = try TestLibrary()
        let book = try t.add("A", status: .wantToRead)
        var draft = BookDraft(book: book)
        draft.status = .reading
        draft.startedAt = date(2026, 1, 1)
        try t.library.updateBook(book, with: draft)
        #expect(book.readings?.count == 1 && book.status == .reading)
        draft.status = .read
        try t.library.updateBook(book, with: draft)
        draft = BookDraft(book: book)
        draft.status = .reading
        draft.startedAt = date(2026, 6, 1)
        try t.library.updateBook(book, with: draft)
        #expect(book.readings?.count == 2)
        #expect(book.status == .reading)
        #expect(book.readingsNewestFirst.first?.startedAt == date(2026, 6, 1))
    }

    @Test func wantToReadIsNotListedAsAReading() throws {
        let t = try TestLibrary()
        let book = try t.add("A", status: .wantToRead)
        #expect(book.readingsNewestFirst.isEmpty)
    }

    @Test func updateAndDeleteReadingIncludingTheLastOne() throws {
        let t = try TestLibrary()
        let book = try t.add("A", status: .read, started: date(2019, 1, 12), finished: date(2019, 3, 2), rating: 3)
        let reading = try #require(book.currentReading)
        try t.library.updateReading(reading, startedAt: date(2019, 1, 1), endedAt: date(2019, 4, 1), rating: 5, notes: "Re-read")
        #expect(reading.stars == 5 && reading.endedAt == date(2019, 4, 1) && reading.notes == "Re-read")
        #expect(throws: LibraryError.self) {
            try t.library.updateReading(reading, startedAt: date(2019, 5, 1), endedAt: date(2019, 4, 1), rating: 5, notes: nil)
        }
        #expect(throws: LibraryError.self) {
            try t.library.updateReading(reading, startedAt: nil, endedAt: nil, rating: 0, notes: nil)
        }
        try t.library.deleteReading(reading)
        #expect(book.status == nil)
        #expect(t.library.fetchBooks().count == 1)
    }

    @Test func currentReadingIsTheLatestCreatedNotTheLatestStarted() throws {
        let t = try TestLibrary()
        let book = try t.add("A", status: .read, started: date(2019, 1, 1), finished: date(2019, 2, 1))
        try t.library.readAgain(book)
        let older = try #require(book.readingsNewestFirst.last)
        try t.library.updateReading(older, startedAt: date(2030, 1, 1), endedAt: date(2030, 2, 1), rating: nil, notes: nil)
        #expect(book.status == .reading)
    }
}

@MainActor
struct HalfStarTests {
    @Test func halfStepsAreAcceptedOthersRefused() throws {
        let t = try TestLibrary()
        let book = try t.add("A", status: .read, finished: date(2026, 2, 1), rating: 3.5)
        #expect(book.displayRating == 3.5)
        let reading = try #require(book.currentReading)
        try t.library.updateReading(reading, startedAt: nil, endedAt: date(2026, 2, 1), rating: 0.5, notes: nil)
        #expect(reading.stars == 0.5)
        for bad in [0.0, 0.3, 4.75, 5.5, -1] {
            #expect(throws: LibraryError.self, "\(bad)") {
                try t.library.updateReading(reading, startedAt: nil, endedAt: date(2026, 2, 1), rating: bad, notes: nil)
            }
        }
        #expect(reading.stars == 0.5)
    }

    @Test func halfStarsSurviveUndo() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("A", status: .reading, started: date(2026, 1, 1))
        try t.library.finishReading(book, on: date(2026, 2, 1), rating: 4.5, notes: nil)
        try t.library.updateReading(try #require(book.currentReading), startedAt: date(2026, 1, 1), endedAt: date(2026, 2, 1), rating: 2.5, notes: nil)
        t.undo?.undo()
        #expect(book.currentReading?.stars == 4.5)
        t.undo?.redo()
        #expect(book.currentReading?.stars == 2.5)
    }
}

struct StarClickTests {
    @Test func firstClickWholeSecondHalfThirdWhole() {
        var rating: Double? = nil
        rating = StarClick.rating(afterClicking: 4, current: rating)
        #expect(rating == 4)
        rating = StarClick.rating(afterClicking: 4, current: rating)
        #expect(rating == 3.5)
        rating = StarClick.rating(afterClicking: 4, current: rating)
        #expect(rating == 4)
        #expect(StarClick.rating(afterClicking: 2, current: 3.5) == 2)
        #expect(StarClick.rating(afterClicking: 1, current: 1) == 0.5)
    }
}
