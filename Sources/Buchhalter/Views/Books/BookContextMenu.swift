import SwiftUI
import BuchhalterCore

/// The right-click menu of a book in the list or grid.
struct BookContextMenu: View {
    @Environment(\.library) private var library
    var model: WindowModel
    var book: Book
    var collections: [Collection]
    /// Set when the current list is a collection.
    var currentCollection: Collection?
    var open: () -> Void

    var body: some View {
        Button("Open") { open() }
        Menu("Add to Collection") {
            ForEach(collections) { collection in
                let isMember = (book.collections ?? []).contains { $0 === collection }
                Toggle(collection.name, isOn: Binding(
                    get: { isMember },
                    set: { _ in model.attempt { try library?.toggle(book, in: collection) } }
                ))
            }
            if !collections.isEmpty { Divider() }
            Button("New Collection…") { model.sheet = .newCollection(addingBook: book.id) }
        }
        if let currentCollection {
            Button("Remove from \u{201C}\(currentCollection.name)\u{201D}") {
                model.attempt { try library?.remove(book, from: currentCollection) }
            }
        }
        Divider()
        Button("Delete Book…", role: .destructive) { model.pendingDeleteBookID = book.id }
    }
}
