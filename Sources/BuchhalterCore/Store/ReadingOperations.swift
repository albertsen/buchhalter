import Foundation
import SwiftData

@MainActor
extension Library {
    // MARK: Finish, abandon, read again

    /// Only a book that is being read can be finished. The finish date is the
    /// only required field; it cannot be before the start.
    public func finishReading(
        _ book: Book, on date: Date, rating: Int?, notes: String?
    ) throws {
        guard let reading = book.currentReading, reading.status == .reading else {
            throw LibraryError.noOpenReading
        }
        try validate(rating: rating)
        if let start = reading.startedAt, date < start { throw LibraryError.finishBeforeStart }
        try change("Finish Reading") {
            reading.statusRaw = ReadingStatus.finished.rawValue
            reading.endedAt = date
            reading.rating = rating
            reading.notes = trimmedOrNil(notes)
        }
    }

    public func abandonReading(_ book: Book, on date: Date?, notes: String?) throws {
        guard let reading = book.currentReading, reading.status == .reading else {
            throw LibraryError.noOpenReading
        }
        if let start = reading.startedAt, let date, date < start { throw LibraryError.finishBeforeStart }
        try change("Abandon Reading") {
            reading.statusRaw = ReadingStatus.abandoned.rawValue
            reading.endedAt = date
            reading.notes = trimmedOrNil(notes)
        }
    }

    /// Starts a new reading with today's start date. Refused while a reading
    /// is open (Want to Read or Reading). Earlier readings stay.
    @discardableResult
    public func readAgain(_ book: Book, today: Date = .now) throws -> Reading {
        if let status = book.status, status == .reading || status == .wantToRead {
            throw LibraryError.readingAlreadyOpen
        }
        return try change("Read Again") {
            newReading(for: book, status: .reading, startedAt: Calendar.current.startOfDay(for: today))
        }
    }

    // MARK: Edit and delete

    public func updateReading(
        _ reading: Reading, startedAt: Date?, endedAt: Date?, rating: Int?, notes: String?
    ) throws {
        try validate(rating: rating)
        if let start = startedAt, let end = endedAt, end < start { throw LibraryError.finishBeforeStart }
        try change("Edit Reading") {
            reading.startedAt = startedAt
            reading.endedAt = endedAt
            reading.rating = rating
            reading.notes = trimmedOrNil(notes)
        }
    }

    public func deleteReading(_ reading: Reading) throws {
        try change("Delete Reading") {
            context.delete(reading)
        }
    }

    // MARK: Status from the editor

    /// Applies the editor's status to the book (the caller wraps this in an
    /// undo group). Want to Read to Reading changes the current reading in
    /// place. When the current reading is finished or abandoned, a different
    /// status starts a new reading, so history is never rewritten.
    ///
    /// No status removes the current reading (Want to Read, Reading or
    /// Finished, with its dates, rating and notes; undo brings it back).
    /// Earlier readings stay. An abandoned current reading already shows as
    /// no status in the editor, so it stays too.
    func applyDraftStatus(_ draft: BookDraft, to book: Book) throws {
        guard let target = draft.status else {
            if let current = book.currentReading, current.status != .abandoned {
                context.delete(current)
            }
            return
        }
        try validate(rating: draft.rating)
        let current = book.currentReading
        let today = Calendar.current.startOfDay(for: .now)
        switch target {
        case .wantToRead:
            guard let current else {
                newReading(for: book, status: .wantToRead)
                return
            }
            switch current.status {
            case .wantToRead: break
            case .reading:
                current.statusRaw = ReadingStatus.wantToRead.rawValue
                current.startedAt = nil
            case .finished, .abandoned:
                newReading(for: book, status: .wantToRead)
            }
        case .reading:
            let start = draft.startedAt ?? today
            guard let current else {
                newReading(for: book, status: .reading, startedAt: start)
                return
            }
            switch current.status {
            case .wantToRead, .reading:
                current.statusRaw = ReadingStatus.reading.rawValue
                current.startedAt = start
            case .finished, .abandoned:
                newReading(for: book, status: .reading, startedAt: start)
            }
        case .read:
            let notes = trimmedOrNil(draft.notes)
            guard let current, current.status != .abandoned else {
                let reading = newReading(for: book, status: .finished, startedAt: draft.startedAt)
                reading.endedAt = draft.finishedAt
                reading.rating = draft.rating
                reading.notes = notes
                return
            }
            current.statusRaw = ReadingStatus.finished.rawValue
            current.startedAt = draft.startedAt
            current.endedAt = draft.finishedAt
            current.rating = draft.rating
            current.notes = notes
        }
    }

    @discardableResult
    func newReading(for book: Book, status: ReadingStatus, startedAt: Date? = nil) -> Reading {
        let reading = Reading()
        reading.statusRaw = status.rawValue
        reading.startedAt = startedAt
        context.insert(reading)
        reading.book = book
        return reading
    }

    func validate(rating: Int?) throws {
        if let rating, !(1...5).contains(rating) { throw LibraryError.invalidRating }
    }
}
