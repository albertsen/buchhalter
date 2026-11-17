import SwiftUI
import BuchhalterCore

// Mac-only: the Book menu, enabled from the focused window's selected book.

struct BookCommands: Commands {
    @FocusedValue(\.bookMenu) private var menu

    var body: some Commands {
        CommandMenu("Book") {
            Button("Edit Book…") { menu?.edit() }
                .disabled(menu == nil)
            Button("Start Reading") { menu?.startReading() }
                .disabled(menu?.status != .wantToRead)
            Button("Finish Reading…") { menu?.finish() }
                .disabled(menu?.status != .reading)
            Button("Abandon…") { menu?.abandon() }
                .disabled(menu?.status != .reading)
            Button("Read Again") { menu?.readAgain() }
                .disabled(menu?.status != .finished && menu?.status != .abandoned)
            Divider()
            Menu("Add to Collection") {
                ForEach(menu?.collections ?? []) { item in
                    Toggle(item.name, isOn: Binding(
                        get: { item.isMember },
                        set: { _ in menu?.toggleCollection(item.id) }
                    ))
                }
                if !(menu?.collections.isEmpty ?? true) { Divider() }
                Button("New Collection…") { menu?.newCollection() }
            }
            .disabled(menu == nil)
            Divider()
            // ⌘⌫ as the menu equivalent. A plain ⌫ here would catch Backspace in text fields;
            // the list and grid handle ⌫ with onDeleteCommand.
            Button("Delete Book…") { menu?.delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(menu == nil)
        }
    }
}
