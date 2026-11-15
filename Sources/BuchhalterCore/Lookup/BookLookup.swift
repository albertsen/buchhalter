import Foundation

/// What the sheet does with a finished lookup.
public enum LookupOutcome: Sendable {
    /// Exactly one book matches: fill the sheet at once.
    case single(LookupRecord)
    /// Several match: the user chooses an edition.
    case several(EditionList)
    /// Neither service found a match.
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

    /// The service returned at most 100 records, so older ones may be missing.
    public var isTruncated: Bool { totalCount > DNBService.maximumRecords }
}

/// Runs the sources in order and says what the sheet must do: the Deutsche
/// Nationalbibliothek first, Open Library only when the first has no match.
/// A failure of the first does not fall back, because that would quietly fill
/// a German library from a mostly English source. It touches neither the
/// library nor the draft; the sheet applies the outcome.
public struct BookLookup: Sendable {
    public var primary: any BookLookupService
    public var fallback: any BookLookupService

    public init(primary: any BookLookupService, fallback: any BookLookupService) {
        self.primary = primary
        self.fallback = fallback
    }

    public static let live = BookLookup(primary: DNBService(), fallback: OpenLibraryService())

    /// - Parameter onSource: called on the main actor when Open Library is asked, so the status line can name it.
    /// - Throws: `LookupError.unreachable` for the source that failed, and
    ///   `CancellationError` when the task is cancelled.
    @concurrent
    public func run(
        _ query: LookupQuery, preferredLanguage: String?,
        onSource: @MainActor @Sendable (LookupSource) -> Void
    ) async throws -> LookupOutcome {
        for service in [primary, fallback] {
            if service.source != primary.source { await onSource(service.source) }
            let response = try await service.search(query)
            try Task.checkCancellation()
            let matches = LookupMatching.matches(response.records, for: query)
            switch matches.count {
            case 0: continue
            case 1: return .single(matches[0])
            default:
                let ordered = LookupMatching.ordered(matches, preferredLanguage: preferredLanguage)
                return .several(EditionList(source: service.source, records: ordered, totalCount: response.totalCount))
            }
        }
        return .none
    }

    /// The large cover of a record, downscaled like any stored cover. Nil on
    /// any failure; a missing cover is normal.
    @concurrent
    public func cover(for record: LookupRecord) async -> Data? {
        guard let reference = record.cover, let data = await coverData(for: record, reference, .large) else { return nil }
        return try? await CoverImage.normalize(data)
    }

    /// Find Cover in the detail's cover menu: the first cover either source
    /// has for the book. The queries run in order (see
    /// `LookupQuery.coverQueries`); for each, both sources are asked, and a
    /// source's edition covers are tried before its work covers. Unlike
    /// `run`, a source without a cover (or one that cannot be reached) falls
    /// through to the other: only the image is used, so an Open Library cover
    /// for a German book is fine. At most `maximumCandidates` matching
    /// editions per source and query; a cover is downloaded only once.
    ///
    /// - Returns: the normalized cover, or nil when no source has one.
    /// - Throws: `LookupError.unreachable` for the first failure when no
    ///   source could be reached, and `CancellationError`.
    @concurrent
    public func findCover(_ queries: [LookupQuery], preferredLanguage: String?) async throws -> Data? {
        var failure: LookupError?
        var reached = false
        var tried = Set<String>()
        for query in queries {
            for service in [primary, fallback] {
                let response: LookupResponse
                do {
                    response = try await service.search(query)
                    reached = true
                } catch let error as LookupError {
                    failure = failure ?? error
                    continue
                }
                try Task.checkCancellation()
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
        if !reached, let failure { throw failure }
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
        let service = record.source == primary.source ? primary : fallback
        return await service.coverData(for: reference, size: size)
    }
}
