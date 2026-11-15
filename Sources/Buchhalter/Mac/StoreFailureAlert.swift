import AppKit

// Mac-only. If the store cannot be opened, the app tells the user where it
// looked and why, and quits. It never deletes or recreates the file.

enum StoreFailureAlert {
    static func show(path: String, error: Error) -> Never {
        FileHandle.standardError.write(Data("library: could not open \(path): \(error)\n".utf8))
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "The library could not be opened")
        alert.informativeText = String(localized: "Buchhalter could not open the library at \(path). Nothing was changed.\n\n\(error.localizedDescription)")
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.runModal()
        exit(1)
    }
}
