import SwiftUI
import SwiftData
import BuchhalterCore

/// The iCloud tab: the status of the sync, the copy of the library from before
/// the first sync, and what does not sync. Shared-ready: the buttons call
/// `SyncActions`, which the Mac fills in.
struct ICloudSettingsPane: View {
    @Environment(CloudSyncMonitor.self) private var monitor
    @Environment(\.syncActions) private var actions
    @Environment(\.locale) private var locale
    @Query private var books: [Book]
    @AppStorage(SyncDefaults.legacyCopyDate) private var legacyCopyTime = 0.0
    /// What the library takes on disk, read when the tab appears.
    @State private var bytes: Int64 = 0
    @State private var legacyFolderExists = false

    private var messages: SyncMessages { SyncMessages(locale: locale) }
    private var showsCopy: Bool { legacyCopyTime > 0 && legacyFolderExists }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            syncSection
            if showsCopy { copySection }
            // The Google Books key syncs through iCloud Keychain, the sources do not.
            Text("The book sources and their order stay on this device. They don’t sync.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, BookLookupSettingsPane.margin)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .paneWidth(620)
        .task { refreshDisk() }
        .onChange(of: monitor.state.lastSynced) { refreshDisk() }
    }

    // MARK: Status

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iCloud Sync").font(.system(size: 13, weight: .semibold))
            Text("Books, readings, collections and covers are kept in your private iCloud and show up on every Mac, iPhone and iPad signed in to the same Apple Account.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if monitor.isEnabled {
                switch monitor.state.box {
                case .problem(let problem): problemHint(problem)
                case .syncing(let firstTransfer): statusBox(syncing: true, firstTransfer: firstTransfer, lastSynced: monitor.state.lastSynced)
                case .upToDate(let lastSynced): statusBox(syncing: false, firstTransfer: false, lastSynced: lastSynced)
                }
            }
        }
    }

    private func statusBox(syncing: Bool, firstTransfer: Bool, lastSynced: Date?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    label("Status")
                    HStack(spacing: 6) {
                        if syncing {
                            ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                            Text(verbatim: messages.syncing)
                        } else {
                            Circle().fill(Theme.accent).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text(verbatim: messages.upToDate)
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(syncing ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.tintText))
                }
                GridRow {
                    label("Last synced")
                    Text(verbatim: lastSynced.map { messages.lastSynced($0) } ?? messages.notYet)
                }
                GridRow {
                    label("In iCloud")
                    Text(verbatim: messages.inICloud(books: books.count, bytes: bytes))
                }
            }
            if firstTransfer {
                Text("The first upload of a large library can take a while. You can keep working, and you can quit Buchhalter: it goes on at the next launch.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)) }
        .accessibilityElement(children: .contain)
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .foregroundStyle(.secondary)
            .frame(width: 110, alignment: .trailing)
            .gridColumnAlignment(.trailing)
    }

    private func problemHint(_ problem: SyncProblem) -> some View {
        var isError = false
        if case .failed = problem { isError = true }
        return SettingsHint(
            tone: isError ? .error : .warning,
            message: Text(verbatim: messages.message(for: problem))
        ) {
            if let title = messages.button(for: problem) {
                Button { open(problem) } label: { Text(verbatim: title).underline() }
                    .buttonStyle(.plain)
            }
        }
    }

    private func open(_ problem: SyncProblem) {
        switch problem {
        case .notSignedIn, .turnedOffForApp: actions.openAccountSettings()
        case .storageFull: actions.openStorageSettings()
        case .failed: break
        }
    }

    // MARK: Copy before the first sync

    private var copySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Copy before the first sync").font(.system(size: 13, weight: .semibold))
            Text("Before the library first went to iCloud, Buchhalter kept a copy of it on this Mac, from \(copyDay).")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(verbatim: "~/Library/Application Support/Buchhalter/")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Show in Finder") { actions.showLegacyFolder?() }
            }
        }
    }

    private var copyDay: String {
        BookFormatting(locale: locale).day(Date(timeIntervalSince1970: legacyCopyTime))
    }

    private func refreshDisk() {
        bytes = LibraryLocation.storeBytes(in: LibraryLocation.folder())
        legacyFolderExists = FileManager.default.fileExists(
            atPath: LibraryLocation.legacyFolder(home: LibraryLocation.realHome()).path)
    }
}
