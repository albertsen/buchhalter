import CloudKit
import CoreData
import SwiftData
import SwiftUI
import BuchhalterCore

/// Watches iCloud and feeds `SyncState`. SwiftData has no sync status API, so
/// this listens to the events `NSPersistentCloudKitContainer` posts for its
/// store and to account changes, maps CloudKit and Core Data types onto the
/// core's enums (the core imports no CloudKit) and keeps what must outlive a
/// launch: the last sync date and an unfinished first transfer. After every
/// successful download and once at launch it merges what two devices created
/// twice (`Library.mergeSyncDuplicates`) and turns the old global sort, which
/// an older app on another device can still write, into each list's own
/// (`Library.adoptGlobalSort`).
///
/// With no container id (a scratch store under `BUCHHALTER_HOME`, or a build
/// without the iCloud entitlement) nothing is observed and `isEnabled` is false.
@Observable
final class CloudSyncMonitor {
    private(set) var state: SyncState
    let containerID: String?
    var isEnabled: Bool { containerID != nil }

    @ObservationIgnored private let modelContainer: ModelContainer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var quietTasks: [SyncEventKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var mergeTask: Task<Void, Never>?

    init(containerID: String?, modelContainer: ModelContainer, defaults: UserDefaults = .standard) {
        self.containerID = containerID
        self.modelContainer = modelContainer
        self.defaults = defaults
        let transfer = defaults.string(forKey: SyncDefaults.firstTransfer).flatMap(FirstTransfer.init(rawValue:))
        state = SyncState(firstTransfer: transfer, lastSynced: defaults.object(forKey: SyncDefaults.lastSynced) as? Date)
    }

    // MARK: Start

    /// Starts watching. A first transfer left over from the last launch goes
    /// on: its quiet period starts again.
    func start() {
        guard isEnabled, observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            guard let event else { return }
            let report = EventReport(event)
            MainActor.assumeIsolated { self?.handle(report) }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccount() }
        })
        refreshAccount()
        switch state.firstTransfer {
        case .upload:
            state.firstUploadBegan(at: .now)
            scheduleQuietPeriod(.upload)
        case .download:
            state.firstDownloadBegan(at: .now)
            scheduleQuietPeriod(.download)
        case nil:
            break
        }
        scheduleMerge(after: .seconds(3))
    }

    /// The first launch of the synced version: the library was copied, so it
    /// goes up now.
    func beginFirstUpload() {
        guard isEnabled else { return }
        defaults.set(FirstTransfer.upload.rawValue, forKey: SyncDefaults.firstTransfer)
        state.firstUploadBegan(at: .now)
    }

    /// A new store without a library to copy: iCloud may hold one to download.
    func beginFirstDownload() {
        guard isEnabled else { return }
        defaults.set(FirstTransfer.download.rawValue, forKey: SyncDefaults.firstTransfer)
        state.firstDownloadBegan(at: .now)
    }

    // MARK: Account

    private func refreshAccount() {
        guard let containerID else { return }
        Task { [weak self] in
            let status = try? await CKContainer(identifier: containerID).accountStatus()
            switch status {
            case .available: self?.state.account(.available)
            case .noAccount, .restricted: self?.state.account(.unavailable)
            // Could not be determined, or only for now: say nothing until it is known.
            default: break
            }
        }
    }

    // MARK: Events

    /// The parts of an event the monitor uses, as plain values.
    private struct EventReport: Sendable {
        var kind: SyncEventKind
        var finished: Bool
        var succeeded: Bool
        var error: SyncError?

        nonisolated init(_ event: NSPersistentCloudKitContainer.Event) {
            switch event.type {
            case .setup: kind = .setup
            case .import: kind = .download
            case .export: kind = .upload
            @unknown default: kind = .setup
            }
            finished = event.endDate != nil
            succeeded = event.succeeded
            error = event.error.map(SyncErrorMapping.map)
        }
    }

    private func handle(_ report: EventReport) {
        if !report.finished {
            quietTasks[report.kind]?.cancel()
            state.eventStarted(report.kind)
            return
        }
        state.eventEnded(report.kind, success: report.succeeded, error: report.error, at: .now)
        persist()
        guard report.succeeded else { return }
        scheduleQuietPeriod(report.kind)
        if report.kind == .download { scheduleMerge(after: .seconds(2)) }
    }

    /// After the quiet period the reducer decides whether the first transfer is over.
    private func scheduleQuietPeriod(_ kind: SyncEventKind) {
        guard state.firstTransfer != nil else { return }
        quietTasks[kind]?.cancel()
        quietTasks[kind] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SyncState.quietPeriod + 1))
            guard !Task.isCancelled, let self else { return }
            state.quietPeriodPassed(kind, at: .now)
            persist()
        }
    }

    private func persist() {
        if let lastSynced = state.lastSynced { defaults.set(lastSynced, forKey: SyncDefaults.lastSynced) }
        if let transfer = state.firstTransfer {
            defaults.set(transfer.rawValue, forKey: SyncDefaults.firstTransfer)
        } else {
            defaults.removeObject(forKey: SyncDefaults.firstTransfer)
        }
    }

    // MARK: Duplicates

    /// Several imports arrive in a row; one merge after the last is enough.
    private func scheduleMerge(after delay: Duration) {
        mergeTask?.cancel()
        mergeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            let library = Library(context: modelContainer.mainContext)
            do {
                let removed = try library.mergeSyncDuplicates()
                if removed > 0 {
                    FileHandle.standardError.write(Data("sync: merged \(removed) duplicates\n".utf8))
                }
            } catch {
                FileHandle.standardError.write(Data("sync: merging duplicates failed: \(error)\n".utf8))
            }
            do {
                if try library.adoptGlobalSort() {
                    FileHandle.standardError.write(Data("sync: gave every list the global sort\n".utf8))
                }
            } catch {
                FileHandle.standardError.write(Data("sync: adopting the global sort failed: \(error)\n".utf8))
            }
        }
    }
}

// MARK: Error mapping

/// CloudKit's errors, reduced to what the user is told apart. The code can sit
/// at the top, in a partial failure, or in an underlying error.
enum SyncErrorMapping {
    nonisolated static func map(_ error: any Error) -> SyncError {
        let error = error as NSError
        if has(error, code: .quotaExceeded) { return .quotaExceeded }
        if has(error, code: .notAuthenticated) { return .notAuthenticated }
        return .other(error.localizedDescription)
    }

    private nonisolated static func has(_ error: NSError, code: CKError.Code, depth: Int = 0) -> Bool {
        guard depth < 4 else { return false }
        if error.domain == CKError.errorDomain, error.code == code.rawValue { return true }
        let partial = (error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Any])?.values ?? [:].values
        for case let inner as NSError in partial where has(inner, code: code, depth: depth + 1) { return true }
        if let inner = error.userInfo[NSUnderlyingErrorKey] as? NSError { return has(inner, code: code, depth: depth + 1) }
        return false
    }
}
