import Foundation

/// The user's order of the book sources and which are switched on, stored as
/// "dnb:on,openLibrary:on,googleBooks:off". It is a per-Mac preference like
/// `LibraryListOrder`, so it lives in UserDefaults, not in the store, and does
/// not sync.
public struct LookupSourceList: Equatable, Sendable {
    public struct Entry: Equatable, Identifiable, Sendable {
        public var source: LookupSource
        public var isOn: Bool
        public var id: LookupSource { source }
    }

    /// Always all sources, each once.
    public private(set) var entries: [Entry]

    /// A new user: the Deutsche Nationalbibliothek, then Open Library, both
    /// on, then Google Books, off until a key is saved.
    private static let defaults = LookupSource.allCases.map { Entry(source: $0, isOn: $0 != .googleBooks) }

    public init() { entries = Self.defaults }

    /// Unknown or repeated entries are dropped and missing sources are added at
    /// the end with their default switch, so a damaged value never hides one.
    public init(raw: String) {
        var seen = Set<LookupSource>()
        var stored: [Entry] = []
        for part in raw.split(separator: ",") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard let name = pieces.first, let source = LookupSource(rawValue: name), seen.insert(source).inserted else { continue }
            let fallback = Self.defaults.first { $0.source == source }?.isOn ?? false
            let isOn = pieces.count > 1 ? (pieces[1] == "on" ? true : pieces[1] == "off" ? false : fallback) : fallback
            stored.append(Entry(source: source, isOn: isOn))
        }
        entries = stored + Self.defaults.filter { !seen.contains($0.source) }
    }

    public var raw: String {
        entries.map { "\($0.source.rawValue):\($0.isOn ? "on" : "off")" }.joined(separator: ",")
    }

    public func isOn(_ source: LookupSource) -> Bool {
        entries.first { $0.source == source }?.isOn ?? false
    }

    public mutating func setOn(_ source: LookupSource, _ isOn: Bool) {
        guard let index = entries.firstIndex(where: { $0.source == source }) else { return }
        entries[index].isOn = isOn
    }

    /// The same contract as `List`'s `onMove`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().filter { entries.indices.contains($0) }.map { entries[$0] }
        var rest = entries.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(insertAt, rest.count)))
        entries = rest
    }

    /// The sources a lookup asks, in order. Google Books counts only with a
    /// saved key, whatever its switch says: a missing key never changes the
    /// stored switch.
    public func active(hasGoogleKey: Bool) -> [LookupSource] {
        entries.filter { $0.isOn && ($0.source != .googleBooks || hasGoogleKey) }.map(\.source)
    }

    /// Google Books stands last among all sources, on or off.
    public var isGoogleBooksLast: Bool { entries.last?.source == .googleBooks }
}
