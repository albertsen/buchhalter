import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif
import BuchhalterCore

/// The main window: sidebar, the books of the selected list, and the detail.
/// It reads with `@Query`, lets core filter, search and sort, and calls
/// `Library` for every change.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(\.locale) private var locale

    @Query private var books: [Book]
    /// Not read directly: observing readings refreshes lists and counts when only a status changes.
    @Query private var readings: [Reading]
    @Query(sort: \Collection.sortIndex) private var collections: [Collection]
    @Query private var settings: [ListSettings]

    @AppStorage("selectedList") private var selectedListRaw = LibraryListID.all.rawValue
    /// The selected book and, in grid mode, the book whose detail is open, so
    /// the window comes back as it was left.
    @AppStorage("selectedBook") private var selectedBookRaw = ""
    @AppStorage("openBook") private var openBookRaw = ""
    @State private var model = WindowModel()
    /// The split view's columns. The Mac leaves them to the user; the iPad
    /// hides the sidebar after a list is picked.
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @FocusState private var searchFocused: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// iPhone: whether a list is pushed over the Library screen. Starts on the
    /// Library screen.
    /// iPad: whether the window is wider than tall; the columns follow it.
    @State private var isLandscape = false
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Changes the iPad's columns without the slide, so a picked list or book
    /// shows at once.
    private func setColumns(_ visibility: NavigationSplitViewVisibility) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { columnVisibility = visibility }
    }
    #if DEBUG
    @State private var sidebarListShown = DebugLaunch.showsList
    #else
    @State private var sidebarListShown = false
    #endif
    @Environment(PhoneUI.self) private var phone
    #endif

    private var library: Library { Library(context: modelContext, undoManager: undoManager) }

    // MARK: Derived state

    /// The selected list; a collection that no longer exists falls back to All Books.
    private var listID: LibraryListID {
        let stored = LibraryListID(rawValue: selectedListRaw) ?? .all
        if case .collection(let id) = stored, !collections.contains(where: { $0.id == id }) { return .all }
        return stored
    }

    private var currentCollection: Collection? {
        if case .collection(let id) = listID { return collections.first { $0.id == id } }
        return nil
    }

    private var listName: String {
        if let collection = currentCollection { return collection.name }
        return listID.builtInName.map { String(localized: $0) } ?? ""
    }

    private var preferences: ListPreferences {
        ListSettings.preferences(for: listID, among: settings, collections: collections)
    }

    private var listBooks: [Book] {
        let inList = LibraryLists.books(in: listID, from: books)
        return BookSorter.sorted(BookSearch.filter(inList, query: model.searchText), by: preferences.sortLevels)
    }

    private var selectedBook: Book? {
        guard let id = model.selectedBookID else { return nil }
        return books.first { $0.id == id }
    }

    private var isSearching: Bool {
        !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Body

    var body: some View {
        let counts = LibraryLists.counts(books: books, collections: collections)
        let visible = listBooks
        Group {
            switch preferences.viewMode {
            case .list:
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar(counts)
                } content: {
                    content(visible, total: counts[listID] ?? 0)
                        .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 520)
                        .navigationTitle(listName)
                        .librarySubtitle(BookFormatting(locale: locale).bookCount(visible.count))
                        #if os(iOS)
                        .phoneListChrome(preferences: preferences, library: library, model: model, listID: listID)
                        #endif
                } detail: {
                    detail(for: selectedBook)
                }
            case .grid:
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar(counts)
                } detail: {
                    NavigationStack(path: $model.gridPath) {
                        content(visible, total: counts[listID] ?? 0)
                            .navigationTitle(listName)
                            .librarySubtitle(BookFormatting(locale: locale).bookCount(visible.count))
                            #if os(iOS)
                            .phoneListChrome(preferences: preferences, library: library, model: model, listID: listID)
                            #endif
                            .navigationDestination(for: UUID.self) { id in
                                detail(for: books.first { $0.id == id })
                            }
                    }
                }
            }
        }
        #if os(macOS)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: Text("Search"))
        .searchFocused($searchFocused)
        .toolbar {
            LibraryToolbar(
                preferences: preferences,
                onSort: { levels in model.attempt { try library.setSortLevels(levels) } },
                onViewMode: { mode in
                    model.attempt { try library.setViewMode(mode, for: listID) }
                    model.gridPath = []
                },
                onAdd: { model.sheet = .addBook },
                onScan: { model.sheet = .scanBarcode }
            )
        }
        #else
        .phoneWindowChrome(model: model, books: books, collections: collections, library: library, reveal: reveal)
        #endif
        .environment(\.library, library)
        .tint(Theme.accent)
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 560)
        #else
        .modifier(PadSplitStyle(isLandscape: isLandscape))
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { landscape in
            guard isPad, landscape != isLandscape else { return }
            isLandscape = landscape
            // Landscape: every column open. Portrait: the detail, the rest a tap away.
            setColumns(landscape ? .all : .detailOnly)
        }
        #endif
        .sheet(item: $model.sheet) { sheet in sheetContent(sheet) }
        .confirmationDialog(deleteBookTitle, isPresented: deleteBookBinding, titleVisibility: .visible) {
            Button("Delete Book", role: .destructive) { deletePendingBook() }
            Button("Cancel", role: .cancel) {}
        } message: {
            #if os(macOS)
            Text("This removes the book and all its readings. You can undo it with ⌘Z.")
            #else
            Text("This removes the book and all its readings. You can undo it.")
            #endif
        }
        .confirmationDialog(deleteCollectionTitle, isPresented: deleteCollectionBinding, titleVisibility: .visible) {
            Button("Delete Collection", role: .destructive) { deletePendingCollection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The books in it stay in your library.")
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .modifier(FindCoverAlertModifier(model: model))
        .focusedSceneValue(\.windowModel, model)
        .focusedSceneValue(\.bookMenu, bookMenuState)
        .onChange(of: model.isSearchFocused) { _, wants in
            if wants {
                searchFocused = true
                model.isSearchFocused = false
            }
        }
        .onChange(of: selectedListRaw) {
            model.selectedBookID = nil
            model.gridPath = []
        }
        .onAppear {
            restoreSelection()
            showSyncNoticeIfNeeded()
            #if os(iOS)
            // iPad: start with the sidebar out, so the lists are the first thing
            // in view, also in portrait; picking a list puts it away.
            if isPad {
                // The geometry callback may not report the first size, so ask the scene.
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                isLandscape = scene?.effectiveGeometry.interfaceOrientation.isLandscape ?? false
                setColumns(.all)
            }
            #endif
            #if os(iOS) && DEBUG
            DebugLaunch.openScreen(model: model, phone: phone)
            #endif
        }
        .onChange(of: model.selectedBookID) { _, id in
            selectedBookRaw = id?.uuidString ?? ""
            #if os(iOS)
            // iPad in portrait: a tapped book gets the whole screen.
            if isPad, !isLandscape, id != nil { setColumns(.detailOnly) }
            #endif
        }
        .onChange(of: model.gridPath) { _, path in openBookRaw = path.last?.uuidString ?? "" }
        .onReceive(NotificationCenter.default.publisher(for: .selectCollection)) { note in
            if let id = note.object as? UUID { selectedListRaw = LibraryListID.collection(id).rawValue }
        }
    }

    // MARK: Columns

    private func sidebar(_ counts: [LibraryListID: Int]) -> some View {
        SidebarView(
            model: model, collections: collections, counts: counts, settings: settings,
            selection: sidebarSelection
        )
        .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 300)
        #if os(iOS)
        .phoneSidebarChrome(model: model, showAllBooks: { sidebarListShown = true; selectedListRaw = LibraryListID.all.rawValue })
        #endif
    }

    /// The sidebar's selection. On the Mac a list is always selected. On an
    /// iPhone the split view is a stack, and no selection is the Library
    /// screen itself, so Back has to be able to clear it.
    private var sidebarSelection: Binding<LibraryListID?> {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            return Binding(
                get: { sidebarListShown ? listID : nil },
                set: { list in
                    if let list { selectedListRaw = list.rawValue }
                    sidebarListShown = list != nil
                }
            )
        }
        return Binding(
            get: { listID },
            set: { list in
                guard let list else { return }
                selectedListRaw = list.rawValue
                // iPad in portrait: the sidebar steps aside once a list is chosen,
                // at once, so the list does not slide in after the books. Grid mode
                // has two columns, so there only the grid stays. Landscape keeps all.
                guard !isLandscape else { return }
                let mode = ListSettings.preferences(for: list, among: settings, collections: collections).viewMode
                setColumns(mode == .grid ? .detailOnly : .doubleColumn)
            }
        )
        #else
        return Binding(get: { listID }, set: { if let list = $0 { selectedListRaw = list.rawValue } })
        #endif
    }

    @ViewBuilder
    private func content(_ visible: [Book], total: Int) -> some View {
        if books.isEmpty {
            EmptyLibraryView { model.sheet = .addBook }
        } else if visible.isEmpty {
            if isSearching {
                NoMatchesView(searchText: model.searchText.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                EmptyListView()
            }
        } else if preferences.viewMode == .list {
            BookListView(model: model, books: visible, collections: collections, currentCollection: currentCollection)
        } else {
            BookGridView(model: model, books: visible, collections: collections, currentCollection: currentCollection)
        }
    }

    @ViewBuilder
    private func detail(for book: Book?) -> some View {
        if let book {
            BookDetailView(
                model: model, book: book, collections: collections,
                usedLanguages: Array(Set(books.compactMap(\.language)))
            )
                .id(book.id)
        } else {
            Text("Select a book")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .addBook:
            BookEditorSheet(
                model: model, editing: nil, books: books, collections: collections,
                onAdded: { id in reveal(id) }, onShowBook: { id in reveal(id) }
            )
            .environment(\.library, library)
        case .addBookTypingISBN:
            BookEditorSheet(
                model: model, editing: nil, books: books, collections: collections,
                onAdded: { id in reveal(id) }, onShowBook: { id in reveal(id) },
                focusISBN: true
            )
            .environment(\.library, library)
        case .scanBarcode:
            ScanSheet(
                mode: .addBooks, model: model, books: books, collections: collections,
                onFinished: { id in if let id { reveal(id) } },
                onShowBook: { id in reveal(id) },
                onTypeISBN: { model.sheet = .addBookTypingISBN }
            )
            .environment(\.library, library)
        case .editBook(let id):
            if let book = book(id) {
                BookEditorSheet(
                    model: model, editing: book, books: books, collections: collections,
                    onAdded: { _ in }, onShowBook: { id in reveal(id) }
                )
                .environment(\.library, library)
            }
        case .finish(let id):
            if let book = book(id) { FinishReadingSheet(model: model, book: book).environment(\.library, library) }
        case .abandon(let id):
            if let book = book(id) { AbandonSheet(model: model, book: book).environment(\.library, library) }
        case .editReading(let bookID, let readingID):
            if let reading = book(bookID)?.readings?.first(where: { $0.id == readingID }) {
                EditReadingSheet(model: model, reading: reading).environment(\.library, library)
            }
        case .newCollection(let bookID):
            NewCollectionSheet(model: model, book: bookID.flatMap(book))
                .environment(\.library, library)
        case .syncNotice:
            SyncNoticeSheet(bookCount: books.count)
        }
    }

    /// After the first launch of the synced version: once, over the window.
    private func showSyncNoticeIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.double(forKey: SyncDefaults.legacyCopyDate) > 0, !defaults.bool(forKey: SyncDefaults.syncNoticeShown),
              model.sheet == nil else { return }
        model.sheet = .syncNotice
    }

    private func book(_ id: UUID) -> Book? { books.first { $0.id == id } }

    /// Selects the book saved at the last quit, and reopens its detail in grid
    /// mode, if it still exists and is in the selected list.
    private func restoreSelection() {
        let visible = Set(listBooks.map(\.id))
        if let id = UUID(uuidString: selectedBookRaw), visible.contains(id) { model.selectedBookID = id }
        if preferences.viewMode == .grid, let id = UUID(uuidString: openBookRaw), visible.contains(id) {
            model.gridPath = [id]
        }
    }

    /// Selects a book, switching to All Books when the current list (or the
    /// search) would hide it.
    private func reveal(_ id: UUID) {
        guard let book = book(id) else {
            // A book added a moment ago may not be in the query result yet.
            model.selectedBookID = id
            selectedListRaw = LibraryListID.all.rawValue
            model.searchText = ""
            model.selectedBookID = id
            return
        }
        if !LibraryLists.contains(book, in: listID) { selectedListRaw = LibraryListID.all.rawValue }
        model.searchText = ""
        model.gridPath = []
        model.selectedBookID = id
    }

    // MARK: Delete

    private var deleteBookBinding: Binding<Bool> {
        Binding(get: { model.pendingDeleteBookID != nil }, set: { if !$0 { model.pendingDeleteBookID = nil } })
    }

    private var deleteBookTitle: LocalizedStringKey {
        if let id = model.pendingDeleteBookID, let title = book(id)?.title {
            return "Delete \u{201C}\(title)\u{201D}?"
        }
        return "Delete Book?"
    }

    private func deletePendingBook() {
        guard let id = model.pendingDeleteBookID, let book = book(id) else { return }
        model.attempt {
            try library.deleteBook(book)
            if model.selectedBookID == id { model.selectedBookID = nil }
            model.gridPath = []
        }
        model.pendingDeleteBookID = nil
    }

    private var deleteCollectionBinding: Binding<Bool> {
        Binding(get: { model.pendingDeleteCollectionID != nil }, set: { if !$0 { model.pendingDeleteCollectionID = nil } })
    }

    private var deleteCollectionTitle: LocalizedStringKey {
        if let id = model.pendingDeleteCollectionID, let name = collections.first(where: { $0.id == id })?.name {
            return "Delete the collection \u{201C}\(name)\u{201D}?"
        }
        return "Delete Collection?"
    }

    private func deletePendingCollection() {
        guard let id = model.pendingDeleteCollectionID, let collection = collections.first(where: { $0.id == id }) else { return }
        model.attempt { try library.deleteCollection(collection) }
        model.pendingDeleteCollectionID = nil
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    // MARK: Book menu

    private var bookMenuState: BookMenuState? {
        guard let book = selectedBook else { return nil }
        let id = book.id
        return BookMenuState(
            bookID: id, status: book.status,
            collections: collections.map { collection in
                .init(
                    id: collection.id, name: collection.name,
                    isMember: (book.collections ?? []).contains { $0 === collection }
                )
            },
            edit: { model.sheet = .editBook(id) },
            finish: { model.sheet = .finish(id) },
            abandon: { model.sheet = .abandon(id) },
            startReading: { model.attempt { try library.startReading(book) } },
            readAgain: { model.attempt { try library.readAgain(book) } },
            toggleCollection: { collectionID in
                if let collection = collections.first(where: { $0.id == collectionID }) {
                    model.attempt { try library.toggle(book, in: collection) }
                }
            },
            newCollection: { model.sheet = .newCollection(addingBook: id) },
            delete: { model.pendingDeleteBookID = id }
        )
    }
}

#if os(iOS)
/// The iPad's split view style: side by side in landscape, the sidebar and
/// the list over the detail in portrait.
private struct PadSplitStyle: ViewModifier {
    var isLandscape: Bool

    func body(content: Content) -> some View {
        if isLandscape {
            content.navigationSplitViewStyle(.balanced)
        } else {
            content.navigationSplitViewStyle(.prominentDetail)
        }
    }
}
#endif
