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

    /// The real home directory. `NSHomeDirectory()` is the app's container in
    /// a sandbox, so this asks the password database instead.
    public static func realHome() -> URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// `<home>/Library/Application Support/Buchhalter`: where the library lived
    /// before the app was sandboxed. Never created here. Pass `realHome()`;
    /// tests pass a temporary folder.
    public static func legacyFolder(home: URL) -> URL {
        home.appending(path: "Library/Application Support/Buchhalter", directoryHint: .isDirectory)
    }

    /// The bytes the library takes in `folder`: the store, its log files and
    /// the external storage folder with the covers. It is what iCloud mirrors,
    /// so Settings shows it as the size "in iCloud" (CloudKit reports no usage
    /// of its own).
    public static func storeBytes(in folder: URL) -> Int64 {
        let fileManager = FileManager.default
        var total: Int64 = 0
        for name in LegacyLibrary.itemNames {
            let url = folder.appending(path: name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let files = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
                while let file = files?.nextObject() as? URL {
                    let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
                }
            } else {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return total
    }
}
