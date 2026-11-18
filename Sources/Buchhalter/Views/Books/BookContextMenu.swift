import SwiftUI
import BuchhalterCore

/// The right-click menu of a book in the list or grid.
struct BookContextMenu: View {
    @Environment(\.library) private var library
    @Environment(\.bookLookup) private var bookLookup
    @Environment(BookSources.self) private var sources
    var model: WindowModel
    var book: Book
    var collections: [Collection]
    /// Set when the current list is a collection.
    var currentCollection: Collection?
    var open: () -> Void

    var body: some View {
        Button("Open") { open() }
        statusActions
        Button("Edit") { model.sheet = .editBook(book.id) }
        if book.synopsis == nil {
            Button("Find Synopsis") {
                BookFinder.findSynopsis(for: book, lookup: bookLookup, sources: sources, library: library, model: model)
            }
            .disabled(model.findingSynopsis.contains(book.id) || !BookFinder.canFindSynopsis(for: book, sources: sources))
        }
        Divider()
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

    /// The next steps for the book's status, as in the detail and the Book menu.
    @ViewBuilder
    private var statusActions: some View {
        switch book.status {
        case .wantToRead:
            Button("Start Reading") { model.attempt { try library?.startReading(book) } }
        case .reading:
            Button("Finish Reading…") { model.sheet = .finish(book.id) }
            Button("Abandon…") { model.sheet = .abandon(book.id) }
        case .finished, .abandoned:
            Button("Read Again") { model.attempt { try library?.readAgain(book) } }
        case nil:
            EmptyView()
        }
    }
}
