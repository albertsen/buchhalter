import SwiftUI
import BuchhalterCore

/// The sheets the main window can show. They carry ids, never model objects.
enum ActiveSheet: Identifiable, Hashable {
    case addBook
    case editBook(UUID)
    case finish(UUID)
    case abandon(UUID)
    case editReading(book: UUID, reading: UUID)
    case newCollection(addingBook: UUID?)

    var id: String {
        switch self {
        case .addBook: "addBook"
        case .editBook(let id): "editBook-\(id)"
        case .finish(let id): "finish-\(id)"
        case .abandon(let id): "abandon-\(id)"
        case .editReading(_, let reading): "editReading-\(reading)"
        case .newCollection(let id): "newCollection-\(id?.uuidString ?? "none")"
        }
    }
}

/// UI state of the one main window. It holds ids and flags only, so nothing
/// outlives the model objects it points at.
@Observable
final class WindowModel {
    var selectedBookID: UUID?
    var searchText = ""
    var isSearchFocused = false
    var sheet: ActiveSheet?
    var pendingDeleteBookID: UUID?
    var pendingDeleteCollectionID: UUID?
    var renamingCollectionID: UUID?
    var isCreatingCollection = false
    /// The NavigationStack path of the detail column in grid mode.
    var gridPath: [UUID] = []
    /// Shown in an alert when an operation fails.
    var errorMessage: String?

    /// Runs a library operation and shows its error, if any, in the window.
    func attempt(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// What the Book menu needs from the selected book, built by `RootView`.
struct BookMenuState {
    var bookID: UUID
    var status: ReadingStatus?
    var collections: [Item]
    var edit: () -> Void
    var finish: () -> Void
    var abandon: () -> Void
    var readAgain: () -> Void
    var toggleCollection: (UUID) -> Void
    var newCollection: () -> Void
    var delete: () -> Void

    struct Item: Identifiable {
        var id: UUID
        var name: String
        var isMember: Bool
    }
}

extension FocusedValues {
    @Entry var windowModel: WindowModel?
    @Entry var bookMenu: BookMenuState?
}
