import SwiftUI
import SwiftData
import BuchhalterCore

// iOS-only: the app on iPhone and iPad. The Mac app is
// Sources/Buchhalter/Mac/BuchhalterMacApp.swift. Both open the same library
// through the same iCloud container.

@main
struct BuchhalterPhoneApp: App {
    /// Nil when the store could not be opened; the window then says why.
    private let container: ModelContainer?
    private let failure: StoreFailure?
    private let syncMonitor: CloudSyncMonitor?
    @State private var sources = BookSources()
    @State private var phone = PhoneUI()
    @Environment(\.scenePhase) private var scenePhase

    static let containerID = "iCloud.de.juergenalbertsen.buchhalter"

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    init() {
        let environment = ProcessInfo.processInfo.environment
        let isScratchStore = !(environment["BUCHHALTER_HOME"] ?? "").isEmpty
        let url: URL
        do {
            url = try LibraryLocation.storeURL()
        } catch {
            (container, syncMonitor) = (nil, nil)
            failure = StoreFailure(path: LibraryLocation.folder().path, message: error.localizedDescription)
            return
        }
        let storeExisted = FileManager.default.fileExists(atPath: url.path)
        // A scratch store never syncs, and neither does the simulator: its builds
        // are unsigned, and CloudKit stops an app without the iCloud entitlement.
        let cloudKitContainer = isScratchStore || Self.isSimulator ? nil : Self.containerID
        print("library: \(url.path)")
        print("sync: \(cloudKitContainer ?? "off")")
        do {
            let made = try LibraryContainer.make(at: url, cloudKitContainer: cloudKitContainer)
            let monitor = CloudSyncMonitor(containerID: cloudKitContainer, modelContainer: made)
            if !storeExisted, UserDefaults.standard.string(forKey: SyncDefaults.firstTransfer) == nil {
                // A new store on this device: iCloud has the library from the Mac.
                monitor.beginFirstDownload()
            }
            monitor.start()
            #if DEBUG
            DebugLaunch.seedIfRequested(made)
            #endif
            container = made
            syncMonitor = monitor
            failure = nil
        } catch {
            // Never deletes or recreates the store; the screen says where it looked.
            (container, syncMonitor) = (nil, nil)
            failure = StoreFailure(path: url.path, message: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container, let syncMonitor {
                RootView()
                    .environment(sources)
                    .environment(syncMonitor)
                    .environment(phone)
                    .environment(\.bookLookup, sources.lookup)
                    .environment(\.scanFeedback, .phone)
                    .modifier(PhoneSyncActionsModifier(phone: phone))
                    .modelContainer(container)
                    .task { await sources.refreshKey() }
                    .onChange(of: scenePhase) { _, phase in
                        // A key saved or removed on another device shows on return.
                        if phase == .active { Task { await sources.refreshKey() } }
                    }
            } else if let failure {
                StoreFailureView(failure: failure)
            }
        }
    }
}

/// Why the library could not be opened, for the one screen the app then shows.
struct StoreFailure {
    var path: String
    var message: String
}

struct StoreFailureView: View {
    var failure: StoreFailure

    var body: some View {
        ContentUnavailableView {
            Label("The library could not be opened", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Buchhalter could not open the library at \(failure.path). Nothing was changed.\n\n\(failure.message)")
        }
    }
}
