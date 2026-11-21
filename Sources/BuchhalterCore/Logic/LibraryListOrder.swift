import Foundation

/// The user's order of the Library rows in the sidebar (the four built-in
/// lists and Authors), stored as "reading,wantToRead,read,all,authors". An
/// order stored before Authors existed gets it at the end. It lives in the library (a `ListSettings`
/// row with the key `sidebarOrder`), so it syncs: dragging Read above Reading
/// changes the order on every device. Before sync it was a UserDefaults
/// preference (`libraryListOrder`); the first launch of the synced app carries
/// it over.
public struct LibraryListOrder: Equatable, Sendable {
    public static let builtIns: [LibraryListID] = [.reading, .wantToRead, .read, .all, .authors]

    /// Always the five Library rows, each once.
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
