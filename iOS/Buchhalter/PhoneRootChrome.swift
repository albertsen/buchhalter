import SwiftUI
import SwiftData
import BuchhalterCore

// iOS-only: what the Mac's window, toolbar and menus do, in the iPhone and
// iPad idiom. `RootView` calls these three modifiers under `#if os(iOS)`.

extension View {
    /// The Library screen (the sidebar): its large title, Settings, Edit, the
    /// search over every book, the bottom bar, and the iCloud states.
    func phoneSidebarChrome(model: WindowModel, showAllBooks: @escaping () -> Void) -> some View {
        modifier(PhoneSidebarChrome(model: model, showAllBooks: showAllBooks))
    }

    /// A list: its search field, the Sort and View menu with `+`, and the
    /// sheet that sorts this list.
    func phoneListChrome(
        preferences: ListPreferences, library: Library, model: WindowModel, listID: LibraryListID, listName: String
    ) -> some View {
        modifier(PhoneListChrome(preferences: preferences, library: library, model: model, listID: listID, listName: listName))
    }

    /// The full-screen scanner, the Settings sheet and the iPad's keyboard
    /// shortcuts.
    func phoneWindowChrome(
        model: WindowModel, books: [Book], collections: [Collection], library: Library, reveal: @escaping (UUID) -> Void
    ) -> some View {
        modifier(PhoneWindowChrome(model: model, books: books, collections: collections, library: library, reveal: reveal))
    }
}

// MARK: Library screen

private struct PhoneSidebarChrome: ViewModifier {
    @Environment(PhoneUI.self) private var phone
    @Environment(CloudSyncMonitor.self) private var syncMonitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var model: WindowModel
    var showAllBooks: () -> Void

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        phone.settings = .bookLookup
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        model.sheet = .newCollection(addingBook: nil)
                    } label: {
                        Label("New Collection", systemImage: "folder.badge.plus")
                    }
                }
                if horizontalSizeClass == .compact {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            phone.scanner = .addBooks
                        } label: {
                            Label("Scan Barcode", systemImage: "barcode.viewfinder")
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            model.sheet = .addBook
                        } label: {
                            Label("Add Book", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .searchable(
                text: $model.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search All Books")
            )
            .onSubmit(of: .search) { showAllBooks() }
            .safeAreaInset(edge: .bottom) {
                if syncMonitor.state.firstTransfer != nil, syncMonitor.state.sidebarLine == .downloading {
                    FirstDownloadNote()
                }
            }
            .overlay {
                if let problem = syncMonitor.state.problem, problem == .notSignedIn || problem == .turnedOffForApp {
                    NoICloudView()
                }
            }
    }
}

/// While the library is first coming from iCloud.
private struct FirstDownloadNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                Text("Downloading your library from iCloud…")
                    .font(.subheadline.weight(.semibold))
                Text("Books appear as they arrive. Covers can take a few minutes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// Not signed in to iCloud, or iCloud off for Buchhalter.
private struct NoICloudView: View {
    @Environment(\.syncActions) private var actions

    var body: some View {
        ContentUnavailableView {
            Label("Your library is in iCloud", systemImage: "exclamationmark.icloud")
        } description: {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Text("Sign in to iCloud on this iPad, or turn on iCloud for Buchhalter, to see the books from your Mac.")
            } else {
                Text("Sign in to iCloud on this iPhone, or turn on iCloud for Buchhalter, to see the books from your Mac.")
            }
        } actions: {
            Button("Open Settings") { actions.openAccountSettings() }
                .buttonStyle(.borderedProminent)
            if UIDevice.current.userInterfaceIdiom == .pad {
                Text("Books you add now stay on this iPad and go to iCloud once you sign in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Books you add now stay on this iPhone and go to iCloud once you sign in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: A list

private struct PhoneListChrome: ViewModifier {
    @Environment(PhoneUI.self) private var phone
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var preferences: ListPreferences
    var library: Library
    var model: WindowModel
    var listID: LibraryListID
    var listName: String

    func body(content: Content) -> some View {
        @Bindable var model = model
        @Bindable var phone = phone
        content
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $model.searchText, placement: .navigationBarDrawer, prompt: Text("Search"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("View", selection: Binding(
                            get: { preferences.viewMode },
                            set: { mode in
                                model.attempt { try library.setViewMode(mode, for: listID) }
                                model.gridPath = []
                            }
                        )) {
                            Label("List", systemImage: "list.bullet").tag(ViewMode.list)
                            Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                        }
                        Button {
                            phone.isSorting = true
                        } label: {
                            Label("Sort Books…", systemImage: "arrow.up.arrow.down")
                        }
                    } label: {
                        Label("Sort and View", systemImage: "arrow.up.arrow.down")
                    }
                }
                // A split view column reports a compact width, so ask the device.
                if UIDevice.current.userInterfaceIdiom == .pad {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            phone.scanner = .addBooks
                        } label: {
                            Label("Scan Barcode", systemImage: "barcode.viewfinder")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.sheet = .addBook
                    } label: {
                        Label("Add Book", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $phone.isSorting) {
                NavigationStack {
                    ScrollView {
                        SortPopover(
                            listName: listName,
                            levels: preferences.sortLevels,
                            onChange: { levels in model.attempt { try library.setSortLevels(levels, for: listID) } }
                        )
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { phone.isSorting = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
    }
}

// MARK: Window

private struct PhoneWindowChrome: ViewModifier {
    @Environment(PhoneUI.self) private var phone
    var model: WindowModel
    var books: [Book]
    var collections: [Collection]
    var library: Library
    var reveal: (UUID) -> Void

    func body(content: Content) -> some View {
        @Bindable var phone = phone
        content
            .fullScreenCover(item: $phone.scanner) { _ in
                ScanScreen(
                    mode: .addBooks, model: model, books: books, collections: collections,
                    onShowBook: { id in
                        phone.scanner = nil
                        reveal(id)
                    },
                    onTypeISBN: {
                        phone.scanner = nil
                        model.sheet = .addBookTypingISBN
                    },
                    onDone: { phone.scanner = nil }
                )
                .environment(\.library, library)
            }
            .sheet(item: $phone.settings) { section in
                PhoneSettingsView(section: section)
            }
            .background { keyboardShortcuts }
    }

    /// The Mac's shortcuts for an iPad with a keyboard. ⌘F comes with the search field.
    private var keyboardShortcuts: some View {
        Group {
            Button("Add Book…") { model.sheet = .addBook }
                .keyboardShortcut("n", modifiers: .command)
            Button("Scan Barcode…") { phone.scanner = .addBooks }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Delete Book…") {
                if let id = model.selectedBookID { model.pendingDeleteBookID = id }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.selectedBookID == nil)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}
