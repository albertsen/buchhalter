import SwiftUI
import BuchhalterCore

/// The lookup state of one Add or Edit Book sheet: what is running, which hint
/// or banner shows, and the edition list while the user chooses. It never
/// writes to the store and holds no model objects; the sheet's draft is the
/// only thing it changes, through a binding.
///
/// Every await point checks the `generation`, so a stopped or replaced lookup
/// never writes late.
@Observable
final class LookupModel {
    enum Phase: Equatable {
        case idle
        case running(LookupQuery, LookupSource)
        case noMatch(LookupQuery)
        /// Every source asked failed; carries the sources asked.
        case unreachable(LookupQuery, [LookupSource])
    }

    private(set) var phase: Phase = .idle
    /// What the last lookup did to the draft: drives the banner, notes and highlights.
    private(set) var result: LookupResult?
    /// The matches to choose from. Setting it presents the picker.
    private(set) var editions: EditionList?
    /// The query behind `editions`, for the picker's headline.
    private(set) var query: LookupQuery?

    private var task: Task<Void, Never>?
    private var generation = UUID()

    var isRunning: Bool {
        if case .running = phase { true } else { false }
    }

    // MARK: Start and stop

    /// Starts a lookup. A running one is replaced and the old banner and notes are cleared.
    func start(_ query: LookupQuery, draft: Binding<BookDraft>, using lookup: BookLookup, library: Library) {
        cancelTask()
        result = nil
        editions = nil
        self.query = query
        phase = .running(query, lookup.sources.first ?? .dnb)
        let generation = generation
        task = Task {
            do {
                let outcome = try await lookup.run(
                    query, preferredLanguage: draft.wrappedValue.language
                ) { [weak self] event in
                    // The status line names the source being asked right now.
                    guard case .asking(let source) = event, let self, self.generation == generation else { return }
                    self.phase = .running(query, source)
                }
                guard self.generation == generation else { return }
                switch outcome {
                case .none:
                    phase = .noMatch(query)
                case .several(let list):
                    phase = .idle
                    editions = list
                case .single(let record):
                    await fill(from: record, draft: draft, using: lookup, library: library, generation: generation)
                }
            } catch let error as LookupError {
                guard self.generation == generation else { return }
                if case .noSourceReached(let sources) = error { phase = .unreachable(query, sources) }
            } catch {
                // Cancelled: `stop()` already reset the state.
            }
        }
    }

    /// The user picked an edition: download its cover and fill the sheet.
    func choose(_ record: LookupRecord, draft: Binding<BookDraft>, using lookup: BookLookup, library: Library) {
        guard let query else { return }
        editions = nil
        phase = .running(query, record.source)
        let generation = generation
        task = Task {
            await fill(from: record, draft: draft, using: lookup, library: library, generation: generation)
        }
    }

    /// The picker was cancelled: nothing changes.
    func cancelEditions() {
        editions = nil
        phase = .idle
    }

    /// Ends a running lookup without changing anything. A late answer is dropped.
    func stop() {
        cancelTask()
        editions = nil
        phase = .idle
    }

    private func cancelTask() {
        task?.cancel()
        task = nil
        generation = UUID()
    }

    /// Downloads the cover, then merges against the draft as it is now, so
    /// values typed during the lookup count as the user's and win.
    private func fill(
        from record: LookupRecord, draft: Binding<BookDraft>, using lookup: BookLookup, library: Library,
        generation: UUID
    ) async {
        let cover = await lookup.cover(for: record)
        guard self.generation == generation, !Task.isCancelled else { return }
        let authors = library.lookupAuthors(record.authors)
        let merged = LookupResult.merge(record, authors: authors, cover: cover, into: draft.wrappedValue)
        draft.wrappedValue = merged.draft
        result = merged.result
        phase = .idle
    }

    // MARK: After filling

    /// Takes over a lookup that ran elsewhere (the iOS scan card), so the
    /// banner, highlights and notes show as if Complete had filled the sheet.
    func adopt(_ result: LookupResult?) {
        self.result = result
        phase = .idle
    }

    /// The hints go away when the user changes the title, the authors or the
    /// ISBN. The banner and the notes stay.
    func clearHint() {
        switch phase {
        case .noMatch, .unreachable: phase = .idle
        case .idle, .running: break
        }
    }

    /// "Use" next to a differing field.
    func use(_ field: LookupField, draft: inout BookDraft) {
        guard var current = result else { return }
        draft = current.use(field, on: draft)
        result = current
    }

    /// The banner's Undo: every filled or used field goes back, and the banner, notes and highlights go away.
    func undo(draft: inout BookDraft) {
        guard let current = result else { return }
        draft = current.undo(on: draft)
        result = nil
    }
}
