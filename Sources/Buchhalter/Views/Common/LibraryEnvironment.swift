import SwiftUI
import BuchhalterCore

private struct LibraryKey: EnvironmentKey {
    static let defaultValue: Library? = nil
}

extension EnvironmentValues {
    /// The library operations on the main context, with the window's undo
    /// manager. Set once by `RootView` so sheets use the same undo stack.
    var library: Library? {
        get { self[LibraryKey.self] }
        set { self[LibraryKey.self] = newValue }
    }
}
