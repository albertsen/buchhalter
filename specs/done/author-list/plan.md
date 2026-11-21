# Author List — Plan

## Current State (audited 2026-11-21)

- `LibraryListID` is the sidebar's selection type and has exhaustive switches in `LibraryLists`, `ListSettings.resolve`, `SidebarView.builtInRow` and `LibraryListID` itself. `LibraryListID.builtIn` (the four book lists) also drives `Library.adoptGlobalSort`, which gives each list in it a `ListSettings` row.
- `LibraryListOrder(raw:)` drops unknown entries and appends missing built-ins at the end. A stored four-list order therefore gets Authors at the end with no migration. An older app drops "authors" from the order when it writes it.
- `Library.setSortName(_:for:)` exists, is used by no view, and its undo action is named "Change Sort Name". An empty value falls back to the guessed sort name.
- `RootView` grid mode is already a two-column split view with a `NavigationStack(path: $model.gridPath)` in the detail column, restored from `openBook`.
- `BookEditorSheet` builds its draft in `init`; there is no way to pass in a first author.

## Research

- Apple, NavigationSplitView (developer.apple.com/documentation/swiftui/navigationsplitview, read 2026-11-21): "You can also embed a NavigationStack in a column"; collapsed, the split view "shows the last column that displays useful information".
- Apple Developer Forums 792882 and 727778: a `NavigationStack` in the content column of a three-column split view gets wrong back navigation on iPhone and needs duplicated `navigationDestination`s. The working arrangement reported is a stack in the second column of a two-column split view. Grid mode already works that way on macOS 27 and iOS 27.

## Decisions

1. **Authors uses the grid-mode shape: sidebar plus a `NavigationStack` in the detail column**, not the three-column split. The alternative, a stack in the content column, is the fragile case above. The stack's root is the author list, `.author(id)` pushes the author's books, and on compact screens `.book(id)` pushes the detail.
2. **Side by side vs pushed:** on the Mac and the iPad in landscape, each stack page is a 360 pt list plus a pane. The root pairs the authors with "No Author Selected"; the author page pairs the books with the book's detail, driven by `model.selectedBookID`. On the iPhone and the iPad in portrait (`userInterfaceIdiom` plus `isLandscape`, see ui.md), each page is the list alone and a book pushes `.book(id)`. The list width is fixed; the content column's draggable width (`listWidth`) does not apply here.
3. **The Mac back button is our own** `‹ Authors` toolbar item with the system one hidden (`navigationBarBackButtonHidden`). macOS draws only a chevron. iOS keeps the system back button, which takes the previous page's title.
4. **`.authors` is a new `LibraryListID` case (raw "authors")** but stays out of `LibraryListID.builtIn`, so `adoptGlobalSort`, `ListSettings` and `LibraryLists.books(in:)` never see it. `LibraryListOrder.builtIns` gets it as the fifth entry. `contains(_:in: .authors)` is false. `counts` adds `.authors`: the number of distinct authors over all books.
5. **Authors come from the books, not from an `Author` query**: the distinct authors of every book's authorships, deduplicated by id. That hides authors without books (spec) at no extra cost, and the existing `@Query` on books keeps the list live.
6. **Sections:** the first character of `TextFolding.fold(sortName)`, uppercased. A–Z is its own section; anything else (digits, Cyrillic, punctuation, an empty sort name) goes under `#`, which comes last. Inside a section the order is `TextFolding.compare` on the sort name, then the name, then the id.
7. **An author's books are sorted with `BookSorter` and the levels `year:asc`.** Its tie rule (title key, then `addedAt`, then id) and nil-last rule are what the spec asks for.
8. **Path:** `WindowModel.authorPath: [AuthorRoute]`, where `AuthorRoute` is `.author(UUID)` or `.book(UUID)`. Changing the list or the path clears `searchText`, because the same field searches authors at the root and books one level down. When the open author's book count drops to 0 (`onChange` of the computed count), the path empties.
9. **Persistence:** a new `@AppStorage("openAuthor")` holds the author id of `authorPath.first`. `restoreSelection` rebuilds `[.author(id)]` when that author still has books, then restores `selectedBook` if it is in that author's list.
10. **Add Book prefill:** `ActiveSheet.addBook` gets an optional author id (`case addBook(author: UUID?)`). The sheet starts with `suggestedAuthor(for:)` of that author's name, so the existing sort name comes along. `reveal(id)` stays in the author's books when the new book has the open author; otherwise it falls back to All Books as today.
11. **Edit Sorted As** reuses `setSortName`, with its action name renamed to "Edit Sorted As" / "Sortierung bearbeiten" (the spec's undo name). That's safe because no UI uses the old name. The sheet is `ActiveSheet.editSortName(UUID)`.
12. **Search prompt:** on the Mac, `.searchable`'s prompt is "Search Authors" at the stack's root and "Search" everywhere else. On iOS, a new `phoneAuthorsChrome` (search, `+`) replaces `phoneListChrome`, which brings the Sort and View menu.

## Components

- `Sources/BuchhalterCore/Logic/LibraryLists.swift`: `.authors` in `LibraryListID` (raw value, `settingsKey` "authors", `builtInName` "Authors"); `contains` and `counts` per Decision 4.
- `Sources/BuchhalterCore/Logic/LibraryListOrder.swift`: `.authors` in `builtIns`; update the doc comment ("five lists").
- `Sources/BuchhalterCore/Logic/AuthorIndex.swift` (new): `AuthorEntry` (id, name, sort name, book count) and `AuthorIndex`. It builds the sections from `[Book]` (Decisions 5 and 6), filters by query (every folded token in the name or the sort name, like `BookSearch`), and returns an author's books sorted (Decision 7). `@MainActor` like `LibraryLists`.
- `Sources/BuchhalterCore/Logic/BookFormatting.swift`: `authorCount(_:)` (catalog plural, "No authors" at 0); `authorBookLine(_:excluding:)` → "1959 · with Lisa Seidl", with the co-authors as an `.and` list and no year part without a year.
- `Sources/BuchhalterCore/Store/BookOperations.swift`: rename the action in `setSortName`.
- `Sources/Buchhalter/App/WindowModel.swift`: `AuthorRoute`, `authorPath`, `ActiveSheet.addBook(author:)`, `.editSortName`.
- `Sources/Buchhalter/Views/Authors/` (new folder, shared): `AuthorListView` (sectioned `List`, one context-menu item, `.sectionIndexTitles` on iOS where available, otherwise none), `AuthorRow`, `AuthorBooksView` (`List` of `BookRow` in a year variant with the same context menu, swipes, drag and `deleteCommand` as `BookListView`), `AuthorsPane` (Decision 2's two layouts and the stack's destinations), `AuthorsEmptyViews` ("No authors yet", "No authors match", "No Author Selected").
- `Sources/Buchhalter/Views/Books/BookRow.swift`: an optional second line in place of the authors, so `AuthorBooksView` reuses the row.
- `Sources/Buchhalter/Views/Sheets/EditSortNameSheet.swift` (new): the sheet from the spec. `Save` is disabled for an empty field.
- `Sources/Buchhalter/Views/Sheets/BookEditorSheet.swift`: an `initialAuthor: AuthorDraft?` init parameter.
- `Sources/Buchhalter/Views/Sidebar/SidebarView.swift`: the Authors row (`person`), count from `counts[.authors]`.
- `Sources/Buchhalter/Views/RootView.swift`: a third layout branch when `listID == .authors`; `openAuthor`; the sheet cases; `reveal`; `restoreSelection`; the search prompt; the Mac toolbar (search and `+` only, plus the back item).
- `iOS/Buchhalter/PhoneRootChrome.swift`: `phoneAuthorsChrome`.
- `iOS/Buchhalter/DebugLaunch.swift`: `-debugScreen authors`, which opens Authors with the first author pushed, for simulator checks.
- `Resources/Localizable.xcstrings`: every text of the spec, through `make strings`, with the German from the spec.
- Docs: architecture.md (`LibraryListID` gains `.authors`; the Data flow "Reading" line names `AuthorIndex`); ui.md (an "Authors" bullet under Mac and under iPhone and iPad; `openAuthor` among the saved keys; Decision 1 and its reason).

## Testing

- `AuthorIndexTests` (new):
  - "Mann, Thomas" goes under M, "Goethe, Johann Wolfgang von" under G, "Ärger, …" under A, "1984 Kollektiv" under `#`, and `#` comes last.
  - The order inside a section follows German collation.
  - An author whose only book is deleted is gone.
  - A book with two authors counts for both.
  - Search finds "boll" in Böll and matches the sort name.
  - The author's books are ordered by year, the same year by title without its article, and a book without a year comes last.
- `LibraryListsTests`: `counts[.authors]` equals the distinct authors; `.authors` round-trips through `rawValue`; `contains(_, in: .authors)` is false.
- `ListSettingsTests` / `SidebarOrderTests`: "read,reading,wantToRead,all" parses to five lists with Authors last. `adoptGlobalSort` creates no "authors" row.
- `BookFormattingTests`: `authorBookLine` with no year, with one co-author and with two (German "mit … und …"); `authorCount` for 0, 1 and 48 in both languages.
- `UndoTests`: the existing `setSortName` undo check also asserts the action name "Edit Sorted As".
- `LocalizationCatalogTests` passes with the new keys.

## Risks

- **Two stacks:** grid mode's `gridPath` and `authorPath` must never both be live. Switching to or from Authors empties the one being left in the same change as `selectedListRaw`, the way `onChange(of: selectedListRaw)` empties `gridPath` today.
- **iPhone back from the author list:** the sidebar binding clears `sidebarListShown` on Back. Authors must go through the same binding, or Back from the list leaves the Library screen out of step.
- **`BookMenuState` and ⌫ on the Mac** read `model.selectedBookID`. On the author page that must be the book selected in `AuthorBooksView`, and it must be cleared when the path pops. Otherwise ⌫ deletes a book that is no longer shown.
- **Exhaustive switches:** adding `.authors` breaks the build in `SidebarView.builtInRow` and `ListSettings.resolve` until they handle it. Don't reach for `default:`, which would hide the next new case too.
