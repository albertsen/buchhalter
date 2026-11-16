import SwiftUI
import BuchhalterCore

/// The sheets the main window can show. They carry ids, never model objects.
enum ActiveSheet: Identifiable, Hashable {
    case addBook
    /// Add Book with the cursor in the ISBN field ("Type ISBN Instead" in the scan sheet).
    case addBookTypingISBN
    case scanBarcode
    case editBook(UUID)
    case finish(UUID)
    case abandon(UUID)
    case editReading(book: UUID, reading: UUID)
    case newCollection(addingBook: UUID?)
    /// The one-time sheet after the first launch of the synced version.
    case syncNotice

    var id: String {
        switch self {
        case .addBook: "addBook"
        case .addBookTypingISBN: "addBookTypingISBN"
        case .scanBarcode: "scanBarcode"
        case .editBook(let id): "editBook-\(id)"
        case .finish(let id): "finish-\(id)"
        case .abandon(let id): "abandon-\(id)"
        case .editReading(_, let reading): "editReading-\(reading)"
        case .newCollection(let id): "newCollection-\(id?.uuidString ?? "none")"
        case .syncNotice: "syncNotice"
        }
    }
}

/// The alerts Find Cover can end in. They have their own state, not
/// `errorMessage`, because "Open Settings…" needs a button of its own and
/// the generic alert has the wrong title.
enum CoverAlert: Equatable {
    /// Every source that is on was asked and none has a cover. Carries
    /// whether to point at Google Books (no key, or switched off).
    case noCover(suggestsGoogleBooks: Bool)
    case noSourceReached
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
    /// Shown by `FindCoverAlertModifier` (Mac-only).
    var coverAlert: CoverAlert?

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
