import SwiftUI
import BuchhalterCore

// iOS-only: the lookup behind the card over the camera.

/// One read ISBN on its way to the library: looks the book up with the
/// user's sources, merges the best match into a draft with the round's
/// preset, and adds it. The card's states are `ScanCard` in the core; this
/// object runs the network and holds the draft. It never writes to the store
/// except in `add`, as one "Add Book" undo step.
@Observable
final class ScanCardModel {
    private(set) var card: ScanCard
    /// The book as it will be added: the ISBN, the round's status and
    /// collections, and the found record merged in.
    var draft: BookDraft
    /// What the merge did, for the editor's banner when the user taps Edit….
    private(set) var result: LookupResult?
    /// True while the chosen edition's cover downloads.
    private(set) var isFilling = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let base: BookDraft

    init(isbn: ISBN, round: ScanRound, language: String?, firstSource: LookupSource) {
        card = ScanCard(isbn: isbn, firstSource: firstSource)
        var fresh = BookDraft()
        fresh.isbnText = isbn.hyphenated
        fresh.language = language
        round.apply(to: &fresh)
        base = fresh
        draft = fresh
    }

    var canAdd: Bool { card.canAdd && !isFilling && draft.canSave }

    // MARK: Lookup

    func start(using lookup: BookLookup, library: Library) {
        task?.cancel()
        generation = UUID()
        let generation = generation
        let query = LookupQuery.isbn(card.isbn, display: card.isbn.hyphenated)
        card.retry(firstSource: lookup.sources.first ?? .dnb)
        task = Task {
            do {
                let outcome = try await lookup.run(query, preferredLanguage: base.language) { [weak self] event in
                    guard case .asking(let source) = event, let self, self.generation == generation else { return }
                    self.card.asking(source)
                }
                guard self.generation == generation else { return }
                card.finished(outcome)
                if let record = card.record { await fill(record, using: lookup, library: library, generation: generation) }
            } catch let error as LookupError {
                guard self.generation == generation else { return }
                if case .noSourceReached = error { card.failedEverywhere() }
            } catch {
                // Cancelled.
            }
        }
    }

    /// Another edition from the picker: its data and cover replace the card's.
    func choose(_ record: LookupRecord, using lookup: BookLookup, library: Library) {
        card.choose(record)
        let generation = generation
        task = Task { await fill(record, using: lookup, library: library, generation: generation) }
    }

    func stop() {
        task?.cancel()
        task = nil
        generation = UUID()
    }

    private func fill(_ record: LookupRecord, using lookup: BookLookup, library: Library, generation: UUID) async {
        isFilling = true
        let cover = await lookup.cover(for: record)
        guard self.generation == generation, !Task.isCancelled else { return }
        let authors = library.lookupAuthors(record.authors)
        // Always from the round's draft, so a second edition does not mix with the first.
        var start = base
        start.status = draft.status
        start.startedAt = draft.startedAt
        start.collectionIDs = draft.collectionIDs
        let merged = LookupResult.merge(record, authors: authors, cover: cover, into: start)
        draft = merged.draft
        result = merged.result
        isFilling = false
    }

    // MARK: Add

    /// Adds the card's book, with origin `lookup` and the record id, as Add
    /// Book stores a looked-up book on the Mac.
    @discardableResult
    func add(using library: Library) throws -> Book {
        if let record = card.record {
            return try library.addBook(draft, origin: .lookup, originNote: record.id)
        }
        return try library.addBook(draft)
    }
}
