import Foundation

/// Where the library lives. `$BUCHHALTER_HOME` replaces the default folder,
/// for agents and manual tests, so the real library is never touched.
public enum LibraryLocation {
    public static let storeFileName = "library.store"

    /// The folder: `$BUCHHALTER_HOME` if set and not empty, else
    /// `~/Library/Application Support/Buchhalter/`. Nothing is created here.
    public static func folder(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let home = environment["BUCHHALTER_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return support.appending(path: "Buchhalter", directoryHint: .isDirectory)
    }

    /// `<folder>/library.store`. Creates the folder when it is missing.
    public static func storeURL(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let folder = folder(environment: environment)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: storeFileName, directoryHint: .notDirectory)
    }
}
