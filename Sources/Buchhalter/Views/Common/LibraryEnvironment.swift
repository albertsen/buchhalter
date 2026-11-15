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

extension EnvironmentValues {
    /// The book data services behind Complete. The injection point for
    /// previews and for the later barcode and assistant features.
    @Entry var bookLookup: BookLookup = .live
}
