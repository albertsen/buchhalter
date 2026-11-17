import SwiftUI
import SwiftData
import BuchhalterCore

// Mac-only: the app, its one window, Settings and menus. The iOS app is
// iOS/BuchhalterPhoneApp.swift.

@main
struct BuchhalterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer
    /// iCloud status for Settings and the sidebar; off for a scratch store.
    private let syncMonitor: CloudSyncMonitor
    /// The book sources and the Google Books key, shared by the main window and Settings.
    @State private var sources = BookSources()

    init() {
        // The one job of the schema bundle: it never opens the library.
        if CloudKitSchemaInitializer.isRequested { CloudKitSchemaInitializer.runAndExit() }

        let environment = ProcessInfo.processInfo.environment
        let isScratchStore = !(environment["BUCHHALTER_HOME"] ?? "").isEmpty
        let url: URL
        do {
            url = try LibraryLocation.storeURL()
        } catch {
            StoreFailureAlert.show(path: LibraryLocation.folder().path, error: error)
        }
        let storeExisted = FileManager.default.fileExists(atPath: url.path)
        // The first launch of the signed app copies the old library into its
        // container, before anything opens the store. Never for a scratch store.
        let copy = isScratchStore ? nil : LegacyLibraryMigration.runIfNeeded(into: url.deletingLastPathComponent())

        let cloudKitContainer = SyncConfiguration.containerIDIfEnabled(isScratchStore: isScratchStore)
        FileHandle.standardError.write(Data("library: \(url.path)\n".utf8))
        FileHandle.standardError.write(Data("sync: \(cloudKitContainer ?? "off")\n".utf8))
        let container: ModelContainer
        do {
            container = try LibraryContainer.make(at: url, cloudKitContainer: cloudKitContainer)
        } catch {
            StoreFailureAlert.show(path: url.path, error: error)
        }
        self.container = container

        let monitor = CloudSyncMonitor(containerID: cloudKitContainer, modelContainer: container)
        if let copy {
            Self.carryOverListOrder(from: copy.preferences, into: container)
            monitor.beginFirstUpload()
        } else if !storeExisted, UserDefaults.standard.string(forKey: SyncDefaults.firstTransfer) == nil {
            // A new store with no library to copy: iCloud may have one for it.
            monitor.beginFirstDownload()
        }
        monitor.start()
        syncMonitor = monitor
    }

    /// The order of the built-in lists was a preference of the old app; with
    /// sync it is part of the library. Written once, from the old preferences.
    private static func carryOverListOrder(from preferences: [String: Any]?, into container: ModelContainer) {
        guard let raw = preferences?[LegacyLibrary.listOrderKey] as? String else { return }
        let library = Library(context: container.mainContext)
        guard !library.hasLibraryListOrder else { return }
        try? library.setLibraryListOrder(LibraryListOrder(raw: raw))
    }

    var body: some Scene {
        // One window, so one undo stack.
        Window("Buchhalter", id: "main") {
            RootView()
                .restoresWindowFrame(named: "main")
                .environment(sources)
                .environment(syncMonitor)
                .environment(\.bookLookup, sources.lookup)
                .environment(\.scanFeedback, .mac)
                .modifier(SyncActionsModifier())
                .task { await sources.refreshKey() }
        }
        .modelContainer(container)
        .commands {
            LibraryCommands()
            BookCommands()
        }
        Settings {
            SettingsView()
                .environment(sources)
                .environment(syncMonitor)
                .modifier(SyncActionsModifier())
                .modelContainer(container)
                .task { await sources.refreshKey() }
        }
    }
}
