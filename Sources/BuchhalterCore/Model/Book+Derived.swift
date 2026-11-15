import Foundation

/// Read-only helpers over a book's relationships. They never mutate anything.
/// The current reading is the one created last (Decision 5), so editing dates
/// cannot change which reading is current.
@MainActor
extension Book {
    public var orderedAuthors: [Author] {
        (authorships ?? [])
            .sorted { $0.position < $1.position }
            .compactMap(\.author)
    }

    /// Readings newest first by creation, including Want to Read.
    var readingsByCreation: [Reading] {
        (readings ?? []).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    public var currentReading: Reading? { readingsByCreation.first }

    public var status: ReadingStatus? {
        currentReading.map { ReadingStatus(raw: $0.statusRaw) }
    }

    public var latestStartedAt: Date? {
        (readings ?? []).compactMap(\.startedAt).max()
    }

    public var latestFinishedAt: Date? {
        (readings ?? [])
            .filter { ReadingStatus(raw: $0.statusRaw) == .finished }
            .compactMap(\.endedAt)
            .max()
    }

    /// Rating of the most recent reading that has one.
    public var displayRating: Double? {
        readingsByCreation.first { $0.stars != nil }?.stars
    }

    /// Readings that are a read-through (reading, finished, abandoned), newest first.
    /// A Want to Read reading is a plan and is not listed.
    public var readingsNewestFirst: [Reading] {
        readingsByCreation.filter { ReadingStatus(raw: $0.statusRaw) != .wantToRead }
    }

    public var origin: BookOrigin { BookOrigin(raw: originRaw) }
}

extension Reading {
    public var status: ReadingStatus { ReadingStatus(raw: statusRaw) }
}
