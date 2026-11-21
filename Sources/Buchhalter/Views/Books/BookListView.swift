import SwiftUI
import BuchhalterCore

/// The middle column in list mode, and an author's books in Authors.
struct BookListView: View {
    @Environment(\.library) private var library
    @Bindable var model: WindowModel
    var books: [Book]
    var collections: [Collection]
    var currentCollection: Collection?
    /// The line in place of the authors (an author's books show the year).
    var rowLine: ((Book) -> String)? = nil
    /// Set where a row pushes the book onto Authors' stack instead of
    /// selecting it (iPhone, iPad in portrait).
    var pushRoute: ((Book) -> AuthorRoute)? = nil

    var body: some View {
        List(selection: $model.selectedBookID) {
            ForEach(books, id: \.id) { book in
                row(book)
                    .tag(book.id)
                    .draggable(BookDragItem(id: book.id))
                    .contextMenu {
                        BookContextMenu(
                            model: model, book: book, collections: collections,
                            currentCollection: currentCollection,
                            open: { model.selectedBookID = book.id }
                        )
                    }
                    #if os(iOS)
                    .swipeActions(edge: .leading) { nextStep(for: book) }
                    .swipeActions(edge: .trailing) {
                        // Asks first, like Delete Book… everywhere else.
                        Button("Delete") { model.pendingDeleteBookID = book.id }
                            .tint(.red)
                    }
                    #endif
            }
        }
        .deleteCommand {
            if let id = model.selectedBookID { model.pendingDeleteBookID = id }
        }
        .accessibilityLabel("Books")
    }

    @ViewBuilder
    private func row(_ book: Book) -> some View {
        let content = BookRow(book: book, isSelected: model.selectedBookID == book.id, lineInsteadOfAuthors: rowLine?(book))
        if let pushRoute {
            NavigationLink(value: pushRoute(book)) { content }
        } else {
            content
        }
    }

    /// Slide right: the next step for the book's status. Read, Abandoned and
    /// no status have none.
    @ViewBuilder
    private func nextStep(for book: Book) -> some View {
        switch book.status {
        case .wantToRead:
            Button("Start Reading") { model.attempt { try library?.startReading(book) } }
                .tint(Theme.accent)
        case .reading:
            Button("Finish Reading…") { model.sheet = .finish(book.id) }
                .tint(Theme.accent)
        case .finished, .abandoned, nil:
            EmptyView()
        }
    }
}
