import Foundation

/// The card over the camera on iPhone and iPad, for one read ISBN: what it
/// shows while the sources are asked, the book it found and the other
/// editions, or why it found none. Pure, so every state is tested without a
/// camera or a network. The scanner's own states (not an ISBN, already in the
/// library) stay in `ScanSession`.
public struct ScanCard: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// The named source is being asked.
        case looking(LookupSource)
        /// `record` is the book on the card.
        case found
        /// Every source answered and none had the ISBN.
        case notFound
        /// Every source asked failed (offline, server error, a refused key).
        case unreachable
    }

    public let isbn: ISBN
    public private(set) var phase: Phase
    /// The book on the card: the best match, or the edition the user chose.
    public private(set) var record: LookupRecord?
    /// Every matching edition, in the edition picker's order (language, then
    /// newest). Empty for a single match.
    public private(set) var editions: [LookupRecord] = []
    /// The editions' list, for the edition picker.
    public private(set) var editionList: EditionList?

    public init(isbn: ISBN, firstSource: LookupSource) {
        self.isbn = isbn
        phase = .looking(firstSource)
    }

    /// "3 other editions": the matches other than the one on the card.
    public var otherEditionCount: Int {
        guard let record else { return 0 }
        return editions.filter { $0.id != record.id }.count
    }

    /// Add and Scan Next works only on a found book.
    public var canAdd: Bool { phase == .found && record != nil }

    // MARK: Events

    public mutating func asking(_ source: LookupSource) {
        guard case .looking = phase else { return }
        phase = .looking(source)
    }

    /// The lookup ended. Several editions put the first (the best match by
    /// the picker's order) on the card.
    public mutating func finished(_ outcome: LookupOutcome) {
        switch outcome {
        case .single(let found):
            record = found
            editions = []
            editionList = nil
            phase = .found
        case .several(let list):
            record = list.records.first
            editions = list.records
            editionList = list
            phase = list.records.isEmpty ? .notFound : .found
        case .none:
            record = nil
            phase = .notFound
        }
    }

    public mutating func failedEverywhere() {
        record = nil
        phase = .unreachable
    }

    /// Try Again on an unreachable card.
    public mutating func retry(firstSource: LookupSource) {
        record = nil
        editions = []
        editionList = nil
        phase = .looking(firstSource)
    }

    /// The user picked another edition in the picker.
    public mutating func choose(_ chosen: LookupRecord) {
        guard editions.contains(where: { $0.id == chosen.id }) else { return }
        record = chosen
    }
}
