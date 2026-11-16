import Foundation

/// One run of "Scan several books in a row": how many books were added, the
/// status and collections the user chose last (preset for the next book) and
/// the book to select when the round ends. A new round starts empty, so its
/// first book gets Add Book's usual defaults.
public struct ScanRound: Equatable, Sendable {
    public struct Preset: Equatable, Sendable {
        public var status: DraftStatus?
        public var collectionIDs: [UUID]
    }

    public private(set) var count = 0
    public private(set) var preset: Preset?
    public private(set) var lastAddedID: UUID?

    public init() {}

    /// Called after a book of the round is saved. What the user chose for it
    /// becomes the preset for the next one, so a change carries on.
    public mutating func recordAdded(_ draft: BookDraft, id: UUID) {
        count += 1
        lastAddedID = id
        preset = Preset(status: draft.status, collectionIDs: draft.collectionIDs)
    }

    /// Applies the preset to the draft of the next book, with the start date
    /// the editor gives a book picked as Reading. Does nothing in the first
    /// book of a round.
    public func apply(to draft: inout BookDraft) {
        guard let preset else { return }
        draft.status = preset.status
        if preset.status == .reading, draft.startedAt == nil {
            draft.startedAt = Calendar.current.startOfDay(for: .now)
        }
        draft.collectionIDs = preset.collectionIDs
    }
}
