import SwiftUI
import AppKit

// Mac-only: the `Settings` scene's content. The pane itself is shared-ready.

/// The Settings window: one tab, Book Lookup. The toolbar leaves room for more
/// tabs, such as the Assistant's keys later.
struct SettingsView: View {
    @Environment(BookSources.self) private var sources

    var body: some View {
        TabView {
            Tab("Book Lookup", systemImage: "magnifyingglass") {
                BookLookupSettingsPane()
            }
        }
        .frame(width: 620)
        // "The key works. Google Books is now on" gives way to "…is on" once the window has been closed.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if (note.object as? NSWindow)?.isSheet == false { sources.justSavedKey = false }
        }
    }
}
