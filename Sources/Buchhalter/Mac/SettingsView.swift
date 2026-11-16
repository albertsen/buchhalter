import SwiftUI
import AppKit

// Mac-only: the `Settings` scene's content. The panes themselves are shared-ready.

/// The Settings window: Book Lookup and iCloud. The toolbar leaves room for
/// more tabs, such as the Assistant's keys later. The selected tab is stored
/// so the sidebar's sync line can open it on iCloud.
struct SettingsView: View {
    @Environment(BookSources.self) private var sources
    @AppStorage(SyncDefaults.settingsTab) private var tab = "bookLookup"

    var body: some View {
        TabView(selection: $tab) {
            Tab("Book Lookup", systemImage: "magnifyingglass", value: "bookLookup") {
                BookLookupSettingsPane()
            }
            Tab("iCloud", systemImage: "icloud", value: "iCloud") {
                ICloudSettingsPane()
            }
        }
        .frame(width: 620)
        // "The key works. Google Books is now on" gives way to "…is on" once the window has been closed.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if (note.object as? NSWindow)?.isSheet == false { sources.justSavedKey = false }
        }
    }
}
