import SwiftUI
import SwiftData
import BuchhalterCore

@main
struct BuchhalterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        let url: URL
        do {
            url = try LibraryLocation.storeURL()
        } catch {
            StoreFailureAlert.show(path: LibraryLocation.folder().path, error: error)
        }
        FileHandle.standardError.write(Data("library: \(url.path)\n".utf8))
        do {
            container = try LibraryContainer.make(at: url)
        } catch {
            StoreFailureAlert.show(path: url.path, error: error)
        }
    }

    var body: some Scene {
        // One window, so one undo stack.
        Window("Buchhalter", id: "main") {
            RootView()
        }
        .modelContainer(container)
        .commands {
            LibraryCommands()
            BookCommands()
        }
    }
}
