import SwiftUI
import BuchhalterCore

/// The grid mode: covers in adaptive columns. A double click or Open pushes
/// the book's detail onto the detail column's stack.
struct BookGridView: View {
    var model: WindowModel
    var books: [Book]
    var collections: [Collection]
    var currentCollection: Collection?

    #if os(iOS)
    /// Three covers in a row on an iPhone.
    private let columns = [GridItem(.adaptive(minimum: 90, maximum: 170), spacing: 14, alignment: .top)]
    private let margin: CGFloat = 16
    #else
    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 170), spacing: 20, alignment: .top)]
    private let margin: CGFloat = 24
    #endif

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(books, id: \.id) { book in
                    BookGridCell(book: book, isSelected: model.selectedBookID == book.id)
                        #if os(iOS)
                        // A tap opens the book; touch has no selection step.
                        .onTapGesture { open(book) }
                        #else
                        .onTapGesture(count: 2) { open(book) }
                        .onTapGesture { model.selectedBookID = book.id }
                        #endif
                        .draggable(BookDragItem(id: book.id))
                        .contextMenu {
                            BookContextMenu(
                                model: model, book: book, collections: collections,
                                currentCollection: currentCollection, open: { open(book) }
                            )
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                }
            }
            .padding(margin)
        }
        .focusable()
        .deleteCommand {
            if let id = model.selectedBookID { model.pendingDeleteBookID = id }
        }
    }

    private func open(_ book: Book) {
        model.selectedBookID = book.id
        model.gridPath = [book.id]
    }
}
