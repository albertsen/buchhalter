import Foundation

/// What the sheet does with a finished lookup.
public enum LookupOutcome: Sendable {
    /// Exactly one book matches: fill the sheet at once.
    case single(LookupRecord)
    /// Several match: the user chooses an edition.
    case several(EditionList)
    /// No source found a match.
    case none
}

/// The matches of a lookup, ready for the "Choose an edition" sheet.
public struct EditionList: Equatable, Sendable {
    public var source: LookupSource
    /// Ordered: the draft's language first, then newest first.
    public var records: [LookupRecord]
    /// The service's own total, before the match filter.
    public var totalCount: Int

    public init(source: LookupSource, records: [LookupRecord], totalCount: Int) {
        self.source = source
        self.records = records
        self.totalCount = totalCount
    }

    /// The service returned as many records as it ever does (100), so older ones may be missing.
    public var isTruncated: Bool { source.maximumListedRecords.map { totalCount > $0 } ?? false }
}

/// What happened to one source during a lookup, in the order it happened.
public enum LookupEvent: Equatable, Sendable {
    /// The source is about to be asked, so a status line can name it.
    case asking(LookupSource)
    /// The source answered, with matches or without.
    case answered(LookupSource)
    /// The source could not be asked or refused the key.
    case failed(LookupSource, LookupError)
}

/// Runs the sources the user turned on, in the user's order, and says what the
/// sheet must do. A source that cannot be reached is skipped and the next one
/// is asked; only when every source asked has failed does the lookup fail. It
/// touches neither the library nor the draft; the sheet applies the outcome.
public struct BookLookup: Sendable {
    public typealias Observer = @MainActor @Sendable (LookupEvent) -> Void

    /// The active services, in the order they are asked.
    public var services: [any BookLookupService]
    /// Hears every event of every call, so the app can follow a source's
    /// health (a rejected key) without each caller forwarding it.
    public var observer: Observer?

    public init(services: [any BookLookupService], observer: Observer? = nil) {
        self.services = services
        self.observer = observer
    }

    public static let live = BookLookup(services: [DNBService(), OpenLibraryService()])

    public var sources: [LookupSource] { services.map(\.source) }
    public var isEmpty: Bool { services.isEmpty }

    private func emit(_ event: LookupEvent, _ onEvent: @MainActor @Sendable (LookupEvent) -> Void) async {
        await onEvent(event)
        if let observer { await observer(event) }
    }

    /// - Parameter onEvent: called on the main actor for each source asked and
    ///   what came of it, so the status line can name the source.
    /// - Throws: `LookupError.noSourceReached` when every source asked failed,
    ///   and `CancellationError` when the task is cancelled.
    @concurrent
    public func run(
        _ query: LookupQuery, preferredLanguage: String?,
        onEvent: @MainActor @Sendable (LookupEvent) -> Void
    ) async throws -> LookupOutcome {
        var asked: [LookupSource] = []
        var answered = false
        for service in services {
            asked.append(service.source)
            await emit(.asking(service.source), onEvent)
            let response: LookupResponse
            do {
                response = try await service.search(query)
            } catch let error as LookupError {
                await emit(.failed(service.source, error), onEvent)
                continue
            }
            try Task.checkCancellation()
            answered = true
            await emit(.answered(service.source), onEvent)
            let matches = LookupMatching.matches(response.records, for: query)
            switch matches.count {
            case 0: continue
            case 1: return .single(matches[0])
            default:
                let ordered = LookupMatching.ordered(matches, preferredLanguage: preferredLanguage)
                return .several(EditionList(source: service.source, records: ordered, totalCount: response.totalCount))
            }
        }
        if !answered, !asked.isEmpty { throw LookupError.noSourceReached(asked) }
        return .none
    }

    /// The large cover of a record, downscaled like any stored cover. Nil on
    /// any failure; a missing cover is normal.
    @concurrent
    public func cover(for record: LookupRecord) async -> Data? {
        guard let reference = record.cover, let data = await coverData(for: record, reference, .large) else { return nil }
        return try? await CoverImage.normalize(data)
    }

    /// Find Cover in the detail's cover menu: the first cover any source has
    /// for the book. The queries run in order (see `LookupQuery.coverQueries`);
    /// for each, every source is asked in the user's order, and a source's
    /// edition covers are tried before its work covers. Unlike `run`, a source
    /// without a cover falls through to the next, because only the image is
    /// used: an Open Library cover for a German book is fine. A source that
    /// cannot be reached is skipped. At most `maximumCandidates` matching
    /// editions per source and query; a cover is downloaded only once.
    ///
    /// - Returns: the normalized cover, or nil when no source has one.
    /// - Throws: `LookupError.noSourceReached` when no source answered any
    ///   query, and `CancellationError`.
    @concurrent
    public func findCover(
        _ queries: [LookupQuery], preferredLanguage: String?,
        onEvent: @MainActor @Sendable (LookupEvent) -> Void = { _ in }
    ) async throws -> Data? {
        var asked: [LookupSource] = []
        var reached = false
        var tried = Set<String>()
        for query in queries {
            for service in services {
                if !asked.contains(service.source) { asked.append(service.source) }
                await emit(.asking(service.source), onEvent)
                let response: LookupResponse
                do {
                    response = try await service.search(query)
                    reached = true
                } catch let error as LookupError {
                    await emit(.failed(service.source, error), onEvent)
                    continue
                }
                try Task.checkCancellation()
                await emit(.answered(service.source), onEvent)
                let candidates = LookupMatching.ordered(
                    LookupMatching.matches(response.records, for: query), preferredLanguage: preferredLanguage
                ).prefix(Self.maximumCandidates)
                let references = candidates.compactMap(\.cover) + candidates.compactMap(\.workCover)
                for reference in references where tried.insert(String(describing: reference)).inserted {
                    if let data = await service.coverData(for: reference, size: .large),
                       let normalized = try? await CoverImage.normalize(data) {
                        return normalized
                    }
                    try Task.checkCancellation()
                }
            }
        }
        if !reached, !asked.isEmpty { throw LookupError.noSourceReached(asked) }
        return nil
    }

    /// Editions tried per source by `findCover`.
    public static let maximumCandidates = 5

    /// A small cover for a row of the edition list.
    @concurrent
    public func thumbnail(for record: LookupRecord) async -> Data? {
        guard let reference = record.cover else { return nil }
        return await coverData(for: record, reference, .small)
    }

    private func coverData(for record: LookupRecord, _ reference: CoverReference, _ size: CoverSize) async -> Data? {
        guard let service = services.first(where: { $0.source == record.source }) else { return nil }
        return await service.coverData(for: reference, size: size)
    }
}
