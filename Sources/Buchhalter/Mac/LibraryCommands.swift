import SwiftUI

// Mac-only: menu commands.

/// ⌘N Add Book… replaces the standard New item, with ⇧⌘N Scan Barcode… below
/// it; ⌘F focuses the search field.
struct LibraryCommands: Commands {
    @FocusedValue(\.windowModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Book…") { model?.sheet = .addBook }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model == nil)
            Button("Scan Barcode…") { model?.sheet = .scanBarcode }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find") { model?.isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(model == nil)
        }
    }
}
