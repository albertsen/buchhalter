import SwiftUI
import UIKit
import BuchhalterCore

// iOS-only: state the Mac keeps in its menus and windows, and what the shared
// views ask of the system.

/// The sections of the Settings sheet, which holds the Mac's two tabs.
enum SettingsSection: Hashable, Identifiable {
    case bookLookup, iCloud
    var id: Self { self }
}

/// App-wide UI state of the iOS app: the Settings sheet and the full-screen
/// scanner, which the Mac shows as a window and a sheet.
@Observable
final class PhoneUI {
    /// Non-nil while Settings is shown; the section it scrolls to.
    var settings: SettingsSection?
    /// Non-nil while the scanner covers the screen.
    var scanner: ScanMode?
    /// The sort levels, as a sheet (the Mac's popover).
    var isSorting = false

    enum ScanMode: Identifiable, Hashable {
        /// A round of books, from the Library screen or a list.
        case addBooks
        var id: Self { self }
    }
}

/// Fills `SyncActions`: the iOS Settings app (Buchhalter's page, which also
/// leads to the Apple Account) and the in-app Settings sheet at iCloud. There
/// is no old library folder on iOS.
struct PhoneSyncActionsModifier: ViewModifier {
    var phone: PhoneUI

    func body(content: Content) -> some View {
        content.environment(\.syncActions, SyncActions(
            showLegacyFolder: nil,
            openAccountSettings: { PhoneSystemSettings.openAppSettings() },
            openStorageSettings: { PhoneSystemSettings.openAppSettings() },
            openSyncSettings: { phone.settings = .iCloud }
        ))
    }
}

enum PhoneSystemSettings {
    /// Buchhalter's page in the Settings app: camera access, language, and
    /// from there the Apple Account.
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
