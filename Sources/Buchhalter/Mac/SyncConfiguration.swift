import Foundation
import Security

// Mac-only: whether this process may sync. Asking CloudKit without the
// entitlement crashes, so the app checks its own signature first.

enum SyncConfiguration {
    static let containerID = "iCloud.de.juergenalbertsen.buchhalter"

    /// The container to mirror the library into, or nil when it must stay
    /// local: a separate test store (`BUCHHALTER_HOME`) never syncs, and a
    /// build without the iCloud entitlement (an unsigned `swift run`) cannot.
    static func containerIDIfEnabled(isScratchStore: Bool) -> String? {
        guard !isScratchStore, hasEntitlement("com.apple.developer.icloud-container-identifiers") else { return nil }
        return containerID
    }

    private static func hasEntitlement(_ name: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, name as CFString, nil) != nil
    }
}
