import Foundation

/// State of one reading. Stored as the English raw value; an unknown value
/// from a newer app version falls back to `.wantToRead`.
public enum ReadingStatus: String, CaseIterable, Sendable {
    case wantToRead
    case reading
    case finished
    case abandoned

    public init(raw: String) {
        self = ReadingStatus(rawValue: raw) ?? .wantToRead
    }

    public var displayName: LocalizedStringResource {
        switch self {
        case .wantToRead: "Want to Read"
        case .reading: "Reading"
        case .finished: "Finished"
        case .abandoned: "Abandoned"
        }
    }
}

public enum BookOrigin: String, Sendable {
    case manual, lookup, scan, assistant

    public init(raw: String) {
        self = BookOrigin(rawValue: raw) ?? .manual
    }
}

public enum ViewMode: String, CaseIterable, Sendable {
    case list, grid

    public init(raw: String) {
        self = ViewMode(rawValue: raw) ?? .list
    }
}
