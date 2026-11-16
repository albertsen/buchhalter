import AppKit
import BuchhalterCore

// Mac-only: the first launch of the signed, sandboxed app copies the library
// from before into its container (see `LegacyLibrary` in the core).

enum LegacyLibraryMigration {
    /// What the launch has to do after the copy.
    struct Outcome {
        /// The old app's preferences, when they could be read.
        var preferences: [String: Any]?
    }

    /// Copies the old library into `folder` when the rule says so. Nil when
    /// nothing was copied. The old folder is only read. When the sandbox denies
    /// the read, an open panel asks for the folder once; Cancel starts with an
    /// empty library and the next launch asks again. A copy that fails after
    /// that stops the app with the reason, and nothing was changed.
    static func runIfNeeded(into folder: URL) -> Outcome? {
        let defaults = UserDefaults.standard
        let copyTime = defaults.double(forKey: SyncDefaults.legacyCopyDate)
        let home = LibraryLocation.realHome()
        let legacy = LibraryLocation.legacyFolder(home: home)
        guard LegacyLibrary.needsCopy(
            legacy: legacy, target: folder, hasBooks: LegacyLibrary.storeHasBooks(in: folder),
            copyDate: copyTime > 0 ? Date(timeIntervalSince1970: copyTime) : nil
        ) else { return nil }

        var source = legacy
        var readPreferences = true
        do {
            try LegacyLibrary.copy(from: legacy, to: folder)
        } catch {
            log("could not read \(legacy.path): \(error)")
            guard let picked = LegacyFolderPanel.ask(directory: legacy) else {
                log("copy cancelled, starting with an empty library")
                return nil
            }
            let scoped = picked.startAccessingSecurityScopedResource()
            defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
            do {
                try LegacyLibrary.copy(from: picked, to: folder)
            } catch {
                StoreFailureAlert.showCopyFailure(path: picked.path, error: error)
            }
            source = picked
            readPreferences = false
        }
        defaults.set(Date.now.timeIntervalSince1970, forKey: SyncDefaults.legacyCopyDate)
        log("library: copied from \(source.path)")

        let preferences = readPreferences ? LegacyLibrary.readPreferences(home: home) : nil
        if let preferences {
            // Per-device settings come along once, where this launch has none yet.
            for (key, value) in LegacyLibrary.defaultsToCarryOver(preferences) where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        return Outcome(preferences: preferences)
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("\(line)\n".utf8))
    }
}
