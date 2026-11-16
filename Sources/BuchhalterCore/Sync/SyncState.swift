import Foundation

// MARK: Inputs

/// What iCloud says about the account, reduced to what the status needs. The
/// app maps `CKAccountStatus` onto it, so the core imports no CloudKit.
public enum SyncAccountStatus: Equatable, Sendable {
    case available
    /// Signed out, or iCloud restricted: either way nothing syncs.
    case unavailable
}

/// The three kinds of event `NSPersistentCloudKitContainer` reports.
public enum SyncEventKind: Equatable, Sendable, CaseIterable {
    case setup
    /// Changes going up to iCloud (an export).
    case upload
    /// Changes coming down from iCloud (an import).
    case download
}

/// Why an event failed, reduced to the cases the user is told apart.
public enum SyncError: Equatable, Sendable {
    /// iCloud refuses the app: signed out, or turned off for Buchhalter.
    case notAuthenticated
    case quotaExceeded
    /// Any other error, with the message iCloud reports.
    case other(String)
}

// MARK: Outputs

public enum SyncProblem: Equatable, Sendable {
    case notSignedIn
    case turnedOffForApp
    case storageFull
    case failed(String)
}

/// What the Settings box shows.
public enum SyncBox: Equatable, Sendable {
    /// `lastSynced` is nil before the first sync has finished ("Not yet").
    case upToDate(lastSynced: Date?)
    /// Changes go up or come down. `firstTransfer` adds the grey line about the first upload.
    case syncing(firstTransfer: Bool)
    case problem(SyncProblem)
}

/// What the line at the bottom of the sidebar shows. Everyday syncs never show it.
public enum SyncSidebarLine: Equatable, Sendable {
    case uploading
    case downloading
    case problem
}

/// Which first transfer is under way.
public enum FirstTransfer: String, Equatable, Sendable {
    case upload
    case download
}

// MARK: Reducer

/// The sync status as a pure reducer: account changes and events go in, the
/// box, the sidebar line and the last sync date come out. SwiftData has no
/// status API and no "everything synced" signal, so this is built from the
/// events the CloudKit container posts. No CloudKit and no clock here, which
/// keeps every transition testable without a network.
public struct SyncState: Equatable, Sendable {
    /// A first transfer ends after this long without a new event of its kind
    /// after the last one ended well. A heuristic: there is no completion signal.
    public static let quietPeriod: TimeInterval = 20

    public private(set) var account: SyncAccountStatus?
    public private(set) var problem: SyncProblem?
    public private(set) var firstTransfer: FirstTransfer?
    public private(set) var lastSynced: Date?

    private var running: [SyncEventKind: Int] = [:]
    /// When the first transfer last saw activity of its kind: its start, or the
    /// end of the latest event.
    private var transferActivity: Date?
    /// Whether the latest event of the first transfer's kind ended well.
    private var transferHealthy = true

    public init(firstTransfer: FirstTransfer? = nil, lastSynced: Date? = nil) {
        self.firstTransfer = firstTransfer
        self.lastSynced = lastSynced
    }

    // MARK: Outputs

    public var box: SyncBox {
        if let problem { return .problem(problem) }
        if firstTransfer != nil || running.values.contains(where: { $0 > 0 }) {
            return .syncing(firstTransfer: firstTransfer != nil)
        }
        return .upToDate(lastSynced: lastSynced)
    }

    public var sidebarLine: SyncSidebarLine? {
        if problem != nil { return .problem }
        switch firstTransfer {
        case .upload: return .uploading
        case .download: return .downloading
        case nil: return nil
        }
    }

    // MARK: Inputs

    public mutating func account(_ status: SyncAccountStatus) {
        account = status
        switch status {
        case .unavailable:
            problem = .notSignedIn
        case .available:
            // Signing in is the end of this problem; any other one waits for a good event.
            if problem == .notSignedIn { problem = nil }
        }
    }

    /// The first upload starts: the library was copied into a new store, or a
    /// first launch was interrupted and continues. `at` starts the quiet period.
    public mutating func firstUploadBegan(at date: Date) {
        beginTransfer(.upload, at: date)
    }

    /// A new store was created without a library to copy, and iCloud may hold one.
    public mutating func firstDownloadBegan(at date: Date) {
        beginTransfer(.download, at: date)
    }

    public mutating func eventStarted(_ kind: SyncEventKind) {
        running[kind, default: 0] += 1
    }

    public mutating func eventEnded(_ kind: SyncEventKind, success: Bool, error: SyncError? = nil, at date: Date) {
        running[kind] = max(0, (running[kind] ?? 0) - 1)
        if success {
            problem = nil
            lastSynced = date
        } else {
            problem = Self.problem(for: error, account: account)
        }
        if let transfer = firstTransfer, Self.kind(of: transfer) == kind {
            transferHealthy = success
            if success { transferActivity = date }
        }
    }

    /// The monitor asks after a successful event and waits `quietPeriod`. The
    /// transfer ends only if its kind has nothing running, its latest event
    /// ended well, and the period has really passed.
    public mutating func quietPeriodPassed(_ kind: SyncEventKind, at date: Date) {
        guard let transfer = firstTransfer, Self.kind(of: transfer) == kind,
              (running[kind] ?? 0) == 0, transferHealthy, problem == nil,
              let activity = transferActivity, date.timeIntervalSince(activity) >= Self.quietPeriod
        else { return }
        firstTransfer = nil
        transferActivity = nil
    }

    // MARK: Helpers

    private mutating func beginTransfer(_ transfer: FirstTransfer, at date: Date) {
        firstTransfer = transfer
        transferActivity = date
        transferHealthy = true
    }

    private static func kind(of transfer: FirstTransfer) -> SyncEventKind {
        transfer == .upload ? .upload : .download
    }

    private static func problem(for error: SyncError?, account: SyncAccountStatus?) -> SyncProblem {
        switch error {
        case .quotaExceeded:
            return .storageFull
        case .notAuthenticated:
            // An account that is available but refuses this app: iCloud is off for Buchhalter.
            return account == .available ? .turnedOffForApp : .notSignedIn
        case .other(let message):
            return .failed(message)
        case nil:
            return .failed("")
        }
    }
}
