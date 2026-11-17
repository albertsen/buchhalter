import SwiftUI

/// What the sync views ask the platform to do. Shared views call these
/// closures and know nothing of `NSWorkspace` or `openSettings`; the Mac's
/// `SyncActionsModifier` fills them in. The defaults do nothing, for previews.
struct SyncActions {
    /// Opens the old library folder in the Finder. Nil where there is none (iOS).
    var showLegacyFolder: (() -> Void)? = {}
    /// Opens the Apple Account settings (not signed in, iCloud off for Buchhalter).
    var openAccountSettings: () -> Void = {}
    /// Opens the iCloud storage settings (storage full).
    var openStorageSettings: () -> Void = {}
    /// Opens Buchhalter's Settings on the iCloud tab (the sidebar line).
    var openSyncSettings: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var syncActions = SyncActions()
}

/// The preference keys of the sync feature, in one place.
enum SyncDefaults {
    /// When the first launch of the synced version copied the old library
    /// (seconds since 1970; absent or 0 means no copy was made).
    static let legacyCopyDate = "legacyCopyDate"
    /// Set once the one-time sheet was closed.
    static let syncNoticeShown = "syncNoticeShown"
    /// The Settings tab to show: `bookLookup` or `iCloud`.
    static let settingsTab = "settingsTab"
    static let lastSynced = "iCloudLastSynced"
    static let firstTransfer = "iCloudFirstTransfer"
}
