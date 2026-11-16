import AppKit
import BuchhalterCore

// Mac-only. The sandbox may deny reading the old library folder; then the user
// picks it once in an open panel, which grants the access.

enum LegacyFolderPanel {
    /// Asks for the old library folder, starting at `directory`. Nil on Cancel.
    static func ask(directory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose the Old Library Folder")
        panel.message = String(localized: "Buchhalter needs your permission to copy the library from before the first sync. Choose the folder “Buchhalter” and click Open.")
        panel.prompt = String(localized: "Open")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }
}
