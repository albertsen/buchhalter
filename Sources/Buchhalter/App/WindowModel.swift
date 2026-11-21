import SwiftUI
import BuchhalterCore

/// The sheets the main window can show. They carry ids, never model objects.
enum ActiveSheet: Identifiable, Hashable {
    case addBook
    /// Add Book from an author's books: the author is the first author chip.
    case addBookByAuthor(UUID)
    /// Add Book with the cursor in the ISBN field ("Type ISBN Instead" in the scan sheet).
    case addBookTypingISBN
    case scanBarcode
    case editBook(UUID)
    /// Edit Book opened on the synopsis (Mac: the Synopsis tab; iOS: its page).
    case editSynopsis(UUID)
    case finish(UUID)
    case abandon(UUID)
    case editReading(book: UUID, reading: UUID)
    case newCollection(addingBook: UUID?)
    /// "Edit Sorted As…" on an author in Authors.
    case editSortName(UUID)
    /// The one-time sheet after the first launch of the synced version.
    case syncNotice

    var id: String {
        switch self {
        case .addBook: "addBook"
        case .addBookByAuthor(let id): "addBookByAuthor-\(id)"
        case .addBookTypingISBN: "addBookTypingISBN"
        case .scanBarcode: "scanBarcode"
        case .editBook(let id): "editBook-\(id)"
        case .editSynopsis(let id): "editSynopsis-\(id)"
        case .finish(let id): "finish-\(id)"
        case .abandon(let id): "abandon-\(id)"
        case .editReading(_, let reading): "editReading-\(reading)"
        case .newCollection(let id): "newCollection-\(id?.uuidString ?? "none")"
        case .editSortName(let id): "editSortName-\(id)"
        case .syncNotice: "syncNotice"
        }
    }
}

/// The alerts Find Cover and Find Synopsis can end in. They have their own
/// state, not `errorMessage`, because "Open Settings…" needs a button of its
/// own and the generic alert has the wrong title.
enum FindAlert: Equatable {
    /// Every source that is on was asked and none has a cover. Carries
    /// whether to point at Google Books (no key, or switched off).
    case noCover(suggestsGoogleBooks: Bool)
    /// The same for a synopsis.
    case noSynopsis(suggestsGoogleBooks: Bool)
    case noSourceReached

    var suggestsGoogleBooks: Bool {
        switch self {
        case .noCover(let suggests), .noSynopsis(let suggests): suggests
        case .noSourceReached: false
        }
    }
}

/// A page in Authors' navigation stack, over its root (the authors).
enum AuthorRoute: Hashable {
    /// An author's books.
    case author(UUID)
    /// A book's detail, pushed where the books and the detail are not side by
    /// side (iPhone, iPad in portrait).
    case book(UUID)
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
    /// The NavigationStack path of Authors. Never set while `gridPath` is.
    var authorPath: [AuthorRoute] = []

    /// The author whose books are open in Authors.
    var openAuthorID: UUID? {
        if case .author(let id) = authorPath.first { return id }
        return nil
    }
    /// Shown in an alert when an operation fails.
    var errorMessage: String?
    /// Shown by `FindCoverAlertModifier` (a Mac and an iOS version).
    var findAlert: FindAlert?
    /// Books Find Synopsis is running for, so their menu item is disabled.
    var findingSynopsis: Set<UUID> = []

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
    var startReading: () -> Void
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
