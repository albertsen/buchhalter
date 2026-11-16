import AppKit
import SwiftUI
import BuchhalterCore

// Mac-only: what the sync views ask of the system. System Settings and the
// Finder are AppKit and `openSettings` is a macOS action.

/// Fills `SyncActions` for the views below it: System Settings, the Finder and
/// Buchhalter's own Settings window on the iCloud tab.
struct SyncActionsModifier: ViewModifier {
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SyncDefaults.settingsTab) private var settingsTab = "bookLookup"

    func body(content: Content) -> some View {
        content.environment(\.syncActions, SyncActions(
            showLegacyFolder: {
                NSWorkspace.shared.open(LibraryLocation.legacyFolder(home: LibraryLocation.realHome()))
            },
            openAccountSettings: { SyncSystemSettings.open(SyncSystemSettings.appleAccount) },
            openStorageSettings: { SyncSystemSettings.open(SyncSystemSettings.iCloudStorage) },
            openSyncSettings: {
                settingsTab = "iCloud"
                openSettings()
            }
        ))
    }
}

enum SyncSystemSettings {
    /// The Apple Account pane. The "icloud" scene of the same pane (the pane's
    /// Info.plist lists it) is where the storage is managed.
    static let appleAccount = "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"
    static let iCloudStorage = "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings?icloud"

    static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
