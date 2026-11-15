import SwiftUI
import BuchhalterCore

/// The middle column in list mode.
struct BookListView: View {
    @Bindable var model: WindowModel
    var books: [Book]
    var collections: [Collection]
    var currentCollection: Collection?

    var body: some View {
        List(selection: $model.selectedBookID) {
            ForEach(books, id: \.id) { book in
                BookRow(book: book, isSelected: model.selectedBookID == book.id)
                    .tag(book.id)
                    .draggable(BookDragItem(id: book.id))
                    .contextMenu {
                        BookContextMenu(
                            model: model, book: book, collections: collections,
                            currentCollection: currentCollection,
                            open: { model.selectedBookID = book.id }
                        )
                    }
            }
        }
        .onDeleteCommand {
            if let id = model.selectedBookID { model.pendingDeleteBookID = id }
        }
        .accessibilityLabel("Books")
    }
}
