import Foundation

/// The user's order of the four built-in lists in the sidebar, stored as
/// "reading,wantToRead,read,all". It is a per-Mac view preference like the
/// selected list, so it lives in UserDefaults, not in the store.
public struct LibraryListOrder: Equatable, Sendable {
    public static let builtIns: [LibraryListID] = [.reading, .wantToRead, .read, .all]

    /// Always the four built-in lists, each once.
    public private(set) var lists: [LibraryListID]

    public init() { lists = Self.builtIns }

    /// Unknown or repeated entries are dropped and missing lists are added at
    /// the end in the default order, so a damaged value never hides a list.
    public init(raw: String) {
        var seen = Set<LibraryListID>()
        let stored = raw.split(separator: ",").compactMap { LibraryListID(rawValue: String($0)) }
            .filter { Self.builtIns.contains($0) && seen.insert($0).inserted }
        lists = stored + Self.builtIns.filter { !seen.contains($0) }
    }

    public var raw: String { lists.map(\.rawValue).joined(separator: ",") }

    /// The same contract as `List`'s `onMove`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().filter { lists.indices.contains($0) }.map { lists[$0] }
        var rest = lists.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(insertAt, rest.count)))
        lists = rest
    }
}
