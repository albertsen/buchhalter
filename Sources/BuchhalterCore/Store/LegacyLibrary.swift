import Foundation
import SQLite3

/// The library from before the app was sandboxed, which lived in
/// `~/Library/Application Support/Buchhalter/`. The signed app keeps its
/// library in its own container, so the first launch copies the old one over.
/// The old folder is never changed: it is the copy of the library from before
/// the first sync, and the way back if the first CloudKit launch goes wrong.
public enum LegacyLibrary {
    /// Names of the files and folders that make up a store: the store, SQLite's
    /// write-ahead log and shared memory, and the hidden folder SwiftData keeps
    /// external storage (covers) in.
    static let storeName = LibraryLocation.storeFileName
    static let itemNames = [storeName, "\(storeName)-wal", "\(storeName)-shm", ".library_SUPPORT"]

    /// The settings that carry over once from the old app's preferences
    /// (`local.buchhalter`). They are per device, so they do not sync; the
    /// order of the built-in lists does, and goes into the store instead.
    public static let carriedDefaultsKeys = [
        "lookupSources", "googleBooksKeyState", "selectedList", "selectedBook", "openBook",
        "sidebarWidth", "listWidth", "WindowFrame main", "NSWindow Frame main",
    ]
    /// The old preference that holds the sidebar order. Not in `carriedDefaultsKeys`.
    public static let listOrderKey = "libraryListOrder"
    /// The old app's preferences domain, and its file name in `Library/Preferences`.
    public static let legacyDomain = "local.buchhalter"

    // MARK: Rule

    /// Copy when the old store exists, no copy was made before, and the new
    /// library is missing or holds no books. A library with books is the
    /// user's work and never gets replaced.
    public static func needsCopy(legacy: URL, target: URL, hasBooks: Bool, copyDate: Date?) -> Bool {
        guard copyDate == nil, !hasBooks else { return false }
        return FileManager.default.fileExists(atPath: legacy.appending(path: storeName).path)
            && legacy.standardizedFileURL != target.standardizedFileURL
    }

    /// Whether the store in `folder` holds a book, read straight from the
    /// SQLite file without SwiftData, so a store that CloudKit mirrors is
    /// opened by nobody but the app itself. A missing store, or one that
    /// cannot be read, has none.
    public static func storeHasBooks(in folder: URL) -> Bool {
        let path = folder.appending(path: storeName).path
        guard FileManager.default.fileExists(atPath: path) else { return false }
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            sqlite3_close(database)
            return false
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM ZBOOK", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int64(statement, 0) > 0
    }

    // MARK: Copy

    /// Copies the store, its log files and the external storage folder from
    /// `source` into `destination`. Everything goes into a temporary folder
    /// next to the destination first and is renamed into place afterwards, so a
    /// failure leaves no half library: the destination holds the old files or
    /// none. Only reads from `source`.
    public static func copy(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.appending(path: storeName).path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let staging = destination.appending(path: ".copy-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: staging) }

        var copied: [String] = []
        for name in itemNames {
            let from = source.appending(path: name)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            try fileManager.copyItem(at: from, to: staging.appending(path: name))
            copied.append(name)
        }

        // Out of the way: what the destination held. The store goes last in
        // and first out, so a store never sits beside files of another one.
        for name in itemNames.reversed() {
            let existing = destination.appending(path: name)
            if fileManager.fileExists(atPath: existing.path) { try fileManager.removeItem(at: existing) }
        }
        for name in copied.reversed() {
            try fileManager.moveItem(at: staging.appending(path: name), to: destination.appending(path: name))
        }
    }

    // MARK: Preferences

    /// The preferences to carry over: the keys of `carriedDefaultsKeys`, with
    /// the values as the old plist had them.
    public static func defaultsToCarryOver(_ plist: [String: Any]) -> [String: Any] {
        plist.filter { carriedDefaultsKeys.contains($0.key) }
    }

    /// The old app's preferences file, read without `UserDefaults` (a sandboxed
    /// app reads its own domain only). Nil when the file is missing or cannot be read.
    public static func readPreferences(home: URL) -> [String: Any]? {
        let url = home.appending(path: "Library/Preferences/\(legacyDomain).plist")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
