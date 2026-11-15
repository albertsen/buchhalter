# Library — Plan

## Current State (audited 2026-11-15)

- **Repo:** `/Users/juergen/dev/buchhalter`, branch `main`, 2 commits, no remote. It holds `.gitignore` (`.build/`, `build/`, `.swiftpm/`, `.DS_Store`, `xcuserdata/`, `DerivedData/`, `.claude/settings.local.json`), `AGENTS.md`, `README.md`, `docs/dev/architecture.md`, `specs/planned/library/spec.md`, `specs/{planned,done}/.gitkeep` and `.claude/settings.json`. There is no source code, no `Package.swift`, no `Makefile`, no `Resources/` and no tests. This spec creates all of it.
- **Toolchain:** Xcode 27.2 (27B52), Swift 6.4.2 (swiftlang-6.4.2.1.9), SwiftPM 6.4.2, target `arm64-apple-macosx27.0.0`, SDK `MacOSX27.2.sdk`. The SDK has SwiftData, `_SwiftData_SwiftUI`, SwiftUI, UniformTypeIdentifiers, ImageIO and VisionKit.
- **xcstringstool** is at `/Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool`. I checked `--help` on 2026-11-15:
  - `compile <input-file> --output-directory <dir> [--format stringsAndStringsdict|stringsdictOnly] [--language <lang> …] [--serialization-format text|binary] [--dry-run]`
  - `extract [<options>] <source-files> --output-directory <dir>` with `--modern-localizable-strings` (`String(localized:)`, `LocalizedStringResource`) and `--SwiftUI` (Text and other SwiftUI APIs)
  - `sync <xcstrings> --stringsdata <files…> [--skip-marking-strings-stale]`
- **Signing:** none installed (`security find-identity` finds 0). The app is signed ad-hoc only, bundle id `local.buchhalter`.
- **Patterns to follow (swell, fluff):**
  - `Package.swift` has a display-free core library, an executable target and a test target. Fixtures are read through `#filePath`, not bundled.
  - The Makefile rebuilds `.build/release/<bin>` only when sources change. It assembles `build/<App>.app` with `cp` (binary, `Info.plist`, resources), then runs `codesign --force --sign -` and `lsregister -f`. `make install` copies the bundle to `/Applications` and unregisters the build copy.
  - Neither project uses SwiftPM resources or `Bundle.module`.
  - GUI apps started by agents run in the background with stderr going to a log file.
- **Contradictions the implementer must know:**
  1. architecture.md (Targets, Layout, Localization) says each target has its own `Localizable.xcstrings`, looked up through `Bundle.module`, with `defaultLocalization "en"`. This plan replaces that with one main-bundle catalog (Decision 3), because of Research 2–3. architecture.md is updated in the same change.
  2. architecture.md says Book has "authors (many-to-many)". SwiftData to-many relationships are unordered, and the spec needs a first author. This plan uses an ordered join model (Decision 6).
  3. architecture.md and AGENTS.md say "Run: `open build/Buchhalter.app`". `open` does not pass `BUCHHALTER_HOME` through the shell environment, and `open -h` on this Mac lists `--env VAR=value`. Manual checks use `open --env BUCHHALTER_HOME=… build/Buchhalter.app`, so the real library is never touched.
  4. The spec's German example dates assume a German region format. `-AppleLanguages '(de)'` alone changes the language, not the region (see Risks).

## Research

All findings apply to the locally installed Xcode 27.2, Swift 6.4.2 and macOS 27.2 SDK. The items marked **verify** must be checked locally before code depends on them.

1. **SwiftData undo.** Checked on 2026-11-15 against macOS 27.2: SwiftData's own undo does not persist attribute changes, so the plan's first approach (attaching the window's `undoManager` to the context) was dropped.
   - `.modelContainer(for:isUndoEnabled:)` exists only in the variant that builds the container from model types. `ModelContainer(for:migrationPlan:configurations:)` has no undo switch. Setting `context.undoManager` does register undo actions on save.
   - **What fails.** Undo and redo of inserts and deletes work. Undo of an attribute change (rename a collection, edit a book, finish or abandon a reading) reverts the value in memory only. Afterwards `context.hasChanges` is `false`, so a `save()` writes nothing, the store keeps the new value, and the next fetch (`@Query` or any `FetchDescriptor`) brings it back. A second `ModelContext` on the same container sees the new value too. `processPendingChanges()`, `context.transaction {}`, waiting for autosave and a save after the undo do not help. Only re-assigning a property after the undo marks the context dirty, and nobody knows which properties an undo touched.
   - **Decision.** The context's `undoManager` stays `nil`. `Library` records every action itself as value snapshots and registers its own undo and redo closures (Decision 13). Tests for this are `UndoTests` and `UndoPersistenceTests` (Testing).
   - Sources: developer.apple.com/documentation/swiftdata/reverting-data-changes-using-the-undo-manager (it only says SwiftData registers changes on save), forums 735562, 735709, 764737. No report of this exact symptom was found; the local reproduction is the evidence.
2. **String Catalogs in SwiftPM.**
   - Strings in a package target resolve against `Bundle.module` only when every call passes `bundle: .module`.
   - There are forum reports of `swift build` failing on `.xcstrings` or not generating symbols (forums 739447, useyourloaf.com "swift-package-string-localization", danielsaidi.com 2025-12-02).
   - No source confirms how `.xcstrings` behaves in executable targets.
3. **Main-bundle localization.**
   - AppKit's own menu items and the app's chosen language follow the main bundle's localizations: its `.lproj` folders, `CFBundleLocalizations` and `CFBundleDevelopmentRegion`.
   - Without `de.lproj` or `CFBundleLocalizations` containing `de`, the app runs in English on a German system, whatever the package bundles contain (forums.swift.org 46685, developer.apple.com forums 836440, the CFBundles "Bundle Types" doc).
   - **Consequence:** one catalog `Resources/Localizable.xcstrings`, compiled by the Makefile into `Contents/Resources/{en,de}.lproj`. `Text("…")`, `String(localized:)` and `LocalizedStringResource` from both targets then resolve against `Bundle.main` with no `bundle:` argument.
   - **Verify:** run `xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory build/Buchhalter.app/Contents/Resources --dry-run` and confirm it lists `en.lproj/Localizable.strings`, `de.lproj/Localizable.strings` and `.stringsdict` files for plurals.
4. **Sorting and search cannot be done in `@Query`.**
   - `SortDescriptor` and `#Predicate` cannot do locale collation with diacritic folding, cannot sort through a to-many relationship (first author), and cannot skip leading articles.
   - "Latest reading is finished" cannot be expressed as a predicate either.
   - So views fetch with `@Query`, and BuchhalterCore filters, searches and sorts in memory. Hundreds to a few thousand books is fine for that.
   - Comparison uses `String.compare(_:options:range:locale:)` with `[.caseInsensitive, .diacriticInsensitive, .numeric]` and `Locale(identifier: "de_DE")`, whatever the UI language, as the spec demands. Folding for search uses `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: de_DE)`.
5. **Images.**
   - SwiftUI on macOS 27 has `.dropDestination(for:)` with a `Transferable` that imports `UTType.image` and file URLs, and `.fileImporter(allowedContentTypes: [.image])`.
   - `.onPasteCommand(of:)` is macOS-only API, so it goes into a Mac-only file.
   - Downscaling uses ImageIO (`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`, `CGImageDestination`). ImageIO exists on iOS too, so this stays in BuchhalterCore.
   - Covers are stored in `@Attribute(.externalStorage) var coverImage: Data?`.
6. **Store location.** `ModelConfiguration(url:)` with `~/Library/Application Support/Buchhalter/library.store`, or `$BUCHHALTER_HOME/library.store`.
7. **Formatting.**
   - Day–month–year dates use `Date.FormatStyle().day().month(.abbreviated).year()`.
   - Ranges ("12 Jan – 2 Mar 2019") use `Date.IntervalFormatStyle` with the same fields.
   - The year must not go through the default number formatter: German would print "1.901". It uses `.number.grouping(.never)` or `String(year)`.
8. **`open --env`.** `open -h` on this Mac lists `--env VAR=value` ("Add an environment variable to the launched process"), plus `--stderr PATH`.

## Decisions

1. **Package shape.**
   - `// swift-tools-version:6.2`, Swift 6 language mode, platforms `[.macOS("27.0"), .iOS("27.0")]`.
   - Products: library `BuchhalterCore` (Foundation, SwiftData, ImageIO, CoreGraphics only), executable `buchhalter` (target `Buchhalter`, links AppKit for the Mac-only files), test target `BuchhalterCoreTests` (Swift Testing).
   - The `Buchhalter` target sets `.defaultIsolation(MainActor.self)`. BuchhalterCore marks `@MainActor` explicitly on operations, so its pure logic stays callable from tests and from background work.
   - *Alternative:* tools 5.9 like swell. *Why:* architecture.md asks for a Swift 6 tools version, and 6.2 brings `defaultIsolation` and `@concurrent`.
2. **No package resources and no `defaultLocalization`.** SwiftPM never sees the catalog, because it sits outside any target directory. *Alternative:* per-target catalogs with `Bundle.module`. *Why:* Research 2–3. It is unreliable with `swift build`, and the main bundle still needs `de` for AppKit menus and the app's language choice.
3. **One String Catalog, `Resources/Localizable.xcstrings`, compiled by `make app`.**
   - `xcrun xcstringstool compile` writes `Contents/Resources/{en,de}.lproj`. `Info.plist` carries `CFBundleDevelopmentRegion en` and `CFBundleLocalizations [en, de]`.
   - Keys are the English text, except where one English text needs two German texts. Those get a semantic key with `defaultValue:`. Example: the Abandon sheet's confirm button has key `abandonSheet.confirm`, English "Abandon", German "Lektüre abbrechen", while the detail button "Abandon" → "Abbrechen".
   - BuchhalterCore texts (status names, sort field names, "Sorted as" defaults, validation errors) use `LocalizedStringResource` or `String(localized:)` against `Bundle.main`. In the test runner they fall back to the English key or default value, and tests may rely on that, except for plural forms.
   - A `make strings` target builds with `-emit-localized-strings` and syncs the compiler's `.stringsdata` files into the catalog (`xcstringstool sync`), so new keys show up as `new` and the catalog test fails until German exists. `xcstringstool extract` on the sources alone was tried and rejected: it writes keys with interpolations as `%arg`, not `%@` or `%lld`, which never match at runtime.
   - *Alternative:* hand-written `.strings` files. *Why:* the catalog keeps plurals and both languages in one reviewed file, as AGENTS.md demands.
4. **Built-in lists are computed in core, not stored.** `LibraryListID` is `.reading`, `.wantToRead`, `.read`, `.all` or `.collection(UUID)`. Membership and counts come from `LibraryLists` over the fetched books. *Alternative:* `#Predicate` per list. *Why:* "latest reading" is not expressible as a predicate (Research 4), and one in-memory rule keeps counts and lists consistent.
5. **The current reading is the reading with the latest `createdAt`.**
   - Status, list membership and badges derive from it.
   - Every new book gets exactly one reading (Want to Read, Reading or Read). Read Again creates a new one.
   - A book with no readings (after Delete Reading of its only reading, or a sync that has not delivered them yet) is valid: it appears in All Books and its collections, has no badge, and offers only `Edit`.
   - The Readings section lists readings that are reading, finished or abandoned, newest first. A Want to Read reading is a plan, not a read-through, so it is not listed.
   - *Alternative:* order by `startedAt`. *Why:* editing dates must not change which reading is current.
6. **Ordered authors through an `Authorship` join model** (`position`, `book`, `author`). *Alternative:* a many-to-many `Book.authors` (unordered), or an encoded array of author ids on Book. *Why:* "Author sorts by the first author's sort name" needs a stable order. A join model keeps real relationships, cascade rules and CloudKit compatibility. An id array loses referential integrity.
7. **One `Author` per name, reused across books.**
   - Typing a name that matches an existing author (case- and diacritic-folded, whitespace collapsed) links that author and shows its stored sort name.
   - A new name gets `AuthorName.guessSortName`.
   - Editing "Sorted as" changes the Author, so it applies to all its books.
   - Authors without books are kept, which keeps their corrected sort names.
   - *Alternative:* delete orphaned authors. *Why:* deleting would lose corrections and make undo of a book delete harder.
8. **ISBN storage: two fields.** `isbn13` holds normalized ISBN-13 digits, converted from ISBN-10 when needed, for duplicate matching and search. `isbnText` holds the user's trimmed input, for display and editing. *Alternative:* store only digits and hyphenate for display. *Why:* correct hyphenation needs the ISBN agency's range tables, which we do not ship.
9. **Origin now, lookup ids later.**
   - SchemaV1 Book gets `originRaw: String = "manual"` and `originNote: String?`.
   - Lookup-id fields are not added yet.
   - *Alternative:* add lookup ids now as optionals. *Why:* every book created now really is `manual`, so stamping it now gives later features correct history. The lookup service, and whether it needs one id or several, is still open (architecture.md Open points). A later optional attribute is an additive SchemaV2 change with a lightweight stage, which CloudKit allows.
10. **Per-list sort levels and view mode live in a `ListSettings` model.**
    - Fields: `key` ("reading", "wantToRead", "read", "all" for built-in lists, empty for collections), an optional to-one `collection` (the inverse of `Collection.settings`, cascade from Collection), `sortLevelsRaw: String = ""` (empty means default), `viewModeRaw: String = "list"`, `updatedAt`.
    - Because there is no unique constraint (CloudKit), reads pick the newest `updatedAt` when duplicates exist.
    - *Alternative:* fields on Collection plus UserDefaults for built-in lists. *Why:* one mechanism for all lists, it syncs with CloudKit later, and deleting and undoing a collection carries its settings with it.
11. **Sort levels as a string**, for example `"author:asc,year:asc"`, parsed by `SortLevels`. Unknown fields from a newer app version are skipped. Each field appears at most once. The first level cannot be removed. The default is `[author asc, year asc]`. *Alternative:* a Codable array attribute. *Why:* it is simple, robust against unknown values, and CloudKit-friendly.
12. **Sort and view changes are not undoable.** They go through `Library.withoutUndo`, which saves and registers nothing. *Alternative:* put them on the undo stack. *Why:* the spec's undo list names data changes only. ⌘Z that silently flips a sort order instead of restoring a deleted book would surprise the user.
13. **`Library` does the undo itself, from value snapshots.**
    - Every operation runs through `Library.change(_ name:covers:_:)`. It captures a `LibrarySnapshot` (value records of all books, authors, authorships, readings and collections, with list settings embedded in the collection record), runs the mutation, saves, captures a second snapshot, and turns the difference into an undo diff and a redo diff. Only changed records are kept.
    - It registers one undo step with the `UndoManager`, inside `beginUndoGrouping`/`endUndoGrouping`, with the action name ("Undo Add Book" / German via the catalog). Running the step applies the diff (creates, changes and deletes objects, writing only the fields that differ), saves, and registers the inverse step, which the manager files as redo.
    - Inserts and deletes are done the same way as attribute changes. Nothing relies on SwiftData's own undo registration, which stays off because `context.undoManager` is `nil` (Research 1).
    - Cover bytes are read only for books an operation names in `covers:` (edit, delete, set cover) and for books it adds, so ordinary actions do not load every cover file.
    - `Authorship` got an `id` for this, so records can be matched. SchemaV1 was not shipped yet.
    - *Alternatives:* SwiftData's undo (fails, Research 1); an inverse closure per operation (more code, easy to miss a field). *Why:* one mechanism for all operations, one undo step per user action, and the saved store is always the state the user sees.
    - *Cost:* two in-memory snapshots per action, linear in the number of books. Fine for thousands of books. Revisit with a diff-based capture if it shows.
14. **Undo manager wiring.** `RootView` builds `Library(context:undoManager:)` from the window's environment `undoManager` (the one Edit → Undo and ⌘Z use) and passes it to the sheets through an environment value, so every sheet uses the same stack. The app has a single `Window` scene (id `main`), so there is one window and one undo stack. An `NSApplicationDelegateAdaptor` quits the app when the window closes. *Alternative:* a `WindowGroup`, which gives several windows sharing one main context and contradictory undo stacks.
15. **Grid layout changes the split view.**
    - List mode uses a three-column `NavigationSplitView` (sidebar, list, detail), as in Main.dc.html.
    - Grid mode uses two columns (sidebar, grid spanning the rest), as in Collection.dc.html. There `Open` or a double-click pushes the book's detail onto a `NavigationStack` in the detail column with a back button.
    - *Why:* the design shows no detail pane in grid view, and the stack pattern carries over to iOS.
16. **Duplicate check runs live in the sheet.**
    - When the sheet opens, `DuplicateIndex` is built once from all books (excluding the edited one). While the banner shows, `Add Book`/`Save` is disabled and `Add Anyway` adds.
    - A match is ISBN-13 equality, or folded title equality plus at least one folded author name in common.
    - `Show Book` closes the sheet, selects the book, and switches to All Books when the current list does not contain it.
17. **ISBN error display.** `Add Book`/`Save` is disabled whenever the field is not empty and not valid. The red border and message appear when the significant characters reach 10 or 13 and fail, or when the field loses focus with an incomplete value. The same message is used in both cases ("This ISBN is not valid. Check the last digit."). *Why:* a red field after the first typed digit would be noise.
18. **Title is required.** `Add Book`/`Save` stays disabled while the trimmed title is empty. A book without a title cannot be shown or sorted meaningfully.
19. **Generated cover colour.**
    - The colour is `palette[fnv1a(book.id bytes) % 11]`. `Hasher` must not be used, because it is seeded per launch.
    - The palette is the design's 11 cover colours: #2E4A62, #8A5A2B, #3F6B4E, #6B3F5E, #A0522D, #5A6B2E, #5E4B8A, #2F5F7A, #4A4F57, #7A2E3A, #3A6B6B.
    - It is stored as hex values in core, keyed on the synced `UUID`, so every device shows the same colour.
20. **Cover images are normalized off the main actor.** They are downscaled to a longest side of 1200 px and re-encoded as JPEG at quality 0.85 by `CoverImage.normalize`, an `@concurrent` function. The result `Data` is assigned on the main actor through an operation.
21. **Book drag and drop.** A `BookDragItem` (`Codable`, `Transferable`, holding the book's UUID) uses an exported type `local.buchhalter.book`, declared in `Info.plist` `UTExportedTypeDeclarations` and conforming to `public.data`. Sidebar collection rows accept only that type. *Alternative:* plain text. *Why:* stray text drops must not be mistaken for books.
22. **Keys.**
    - ⌘N is `CommandGroup(replacing: .newItem)`. ⌘F is a Find command that sets `searchFocused`.
    - Esc is handled by the native search field.
    - ⌫ is `.onDeleteCommand` on the list and the grid, so it never fires while a text field has focus.
    - The Book menu's `Delete Book…` carries ⌘⌫ as its menu equivalent. A plain-⌫ menu equivalent would catch Backspace in text fields.
23. **Default language in Add Book** is the language of the most recently added book, or none in an empty library. It is stored as an ISO 639 code and displayed through `Locale.current.localizedString(forLanguageCode:)`. The popup lists the codes already used in the library first, then all two-letter ISO codes sorted by localized name. Nothing extra is stored.
24. **Colours.**
    - The accent #1F6F5C is the app tint.
    - The selection and badge tint #DCEBE6/#14503F, the ISBN error #B3261E and the cover palette are `Theme` constants.
    - The sidebar (#EEF0F2), separators (#DADDE1) and secondary text (#5F6670) come from native sidebar material, `Divider` and `.secondary`, which match the design in light mode.
    - Titles use `.system(…, design: .serif)` (New York).
25. **Store failures never touch the file.** If the container cannot open the store, the app shows an alert with the path and the error, logs it to stderr and quits. It never deletes or recreates `library.store`.

## Components

### `SchemaV1` (BuchhalterCore/Model)
- A `VersionedSchema`, `versionIdentifier 1.0.0`, with models `Book`, `Author`, `Authorship`, `Reading`, `Collection`, `ListSettings`. Top-level `typealias Book = SchemaV1.Book` and so on.
- **Book:** `id: UUID = UUID()`, `title = ""`, `subtitle: String?`, `isbn13: String?`, `isbnText: String?`, `publisher: String?`, `year: Int?`, `pageCount: Int?`, `language: String?`, `originalLanguage: String?` (added during the manual checks, before SchemaV1 shipped), `@Attribute(.externalStorage) coverImage: Data?`, `addedAt = Date.now`, `originRaw = "manual"`, `originNote: String?`. Relationships:
  - `authorships: [Authorship]? = []`, cascade
  - `readings: [Reading]? = []`, cascade
  - `collections: [Collection]? = []`, nullify
- **Author:** `id`, `name = ""`, `sortName = ""`, `authorships: [Authorship]? = []`, cascade.
- **Authorship:** `position = 0`, `book: Book?`, `author: Author?`.
- **Reading:**
  - `id`
  - `statusRaw = "wantToRead"`
  - `startedAt: Date?`
  - `endedAt: Date?` (the finish or abandon date)
  - `rating: Int?`
  - `notes: String?`
  - `createdAt = Date.now`
  - `book: Book?`
- **Collection:** `id`, `name = ""`, `note: String?`, `sortIndex: Double = 0`, `createdAt`, `books: [Book]? = []` (inverse of `Book.collections`), `settings: ListSettings?` (cascade).
- **ListSettings:** as in Decision 10.
- Must not: use `.unique`, use `.deny`, have non-optional relationships, or store enums other than as `String` raw values.

### `LibraryMigrationPlan`
`schemas = [SchemaV1.self]`, `stages = []`.

### `ReadingStatus`, `BookOrigin`, `ViewMode`
- `String` raw-value enums. Unknown raw values map to a safe fallback: status `.wantToRead`, view `.list`.
- `ReadingStatus.displayName: LocalizedStringResource`: Want to Read / Will ich lesen, Reading / Lese ich, Finished / Gelesen, Abandoned / Nicht zu Ende gelesen.

### `Book+Derived`
- Read-only helpers, `@MainActor`:
  - `orderedAuthors: [Author]` (by position)
  - `currentReading`
  - `status: ReadingStatus?`
  - `latestStartedAt`
  - `latestFinishedAt` (most recent finished reading's `endedAt`)
  - `displayRating` (rating of the most recent reading with a rating)
  - `readingsNewestFirst` (excluding Want to Read)
- Must not mutate anything.

### `LibraryLocation` and `LibraryContainer` (Store)
- `LibraryLocation.resolve(environment: [String: String]) -> URL` returns the folder: `$BUCHHALTER_HOME` if set and not empty, else `~/Library/Application Support/Buchhalter/`.
- `storeURL` is `<folder>/library.store`. The folder is created if it is missing.
- `LibraryContainer.make(at:) throws -> ModelContainer` uses the schema of SchemaV1, the migration plan and `ModelConfiguration(url:)`. `LibraryContainer.inMemory()` serves the tests.
- At launch the app logs `library: <path>` to stderr.
- Must not delete, move or overwrite an existing store.

### `Library` (Store, `@MainActor struct`, holds `context: ModelContext`)
- `change<T>(_ name: LocalizedStringResource, covers: [Book] = [], _ body: () throws -> T) throws -> T` handles snapshots, saving and the undo registration (Decision 13). `LibrarySnapshot.swift` holds the records, the diff and `apply(_:)`.
- `withoutUndo(_:)` is used for settings: it saves and registers nothing.
- Operation groups live in separate files, as extensions:
  - **BookOperations:** `addBook(_ draft: BookDraft) throws -> Book`, `updateBook(_:with:)`, `deleteBook(_:)`, `setCover(_ data: Data?, for:)`, `setSortName(_:for author:)`, `resolveAuthors([AuthorDraft]) -> [Author]`, which reuses existing authors.
  - **ReadingOperations:**
    - `finishReading(_ book:, on:, rating:, notes:)`, which requires the current status `.reading` and `endedAt >= startedAt`
    - `abandonReading(_:, on: Date?, notes:)`
    - `readAgain(_:)`, which creates a new reading with status Reading and today's start, and is refused while a reading is open
    - `updateReading(_:startedAt:endedAt:rating:notes:)`
    - `deleteReading(_:)`
    - `applyStatus(_ draftStatus:, to book:)`: Want to Read → Reading transitions the current reading in place. When the current reading is finished or abandoned, choosing Want to Read or Reading starts a new reading, so history is never rewritten.
  - **CollectionOperations:**
    - `validateCollectionName(_:excluding:) -> LibraryError?` (empty after trimming; already taken, compared case- and diacritic-folded)
    - `createCollection(named:) throws -> Collection` (sortIndex after the last)
    - `renameCollection`
    - `deleteCollection` (books stay)
    - `moveCollections(fromOffsets:toOffset:)` (renumbers 0…n)
    - `add(_ book:to:)`, `remove(_:from:)`, `toggle(_:in:)`
    - `createCollection(named:adding book:)`: one undo step for `New Collection…` in the book menu
  - **ListSettingsOperations:** `settings(for: LibraryListID) -> (SortLevels, ViewMode)`, `setSortLevels(_:for:)`, `resetSort(for:)`, `setViewMode(_:for:)`, all without undo.
- Rating is validated to 1…5 or nil. Text fields are trimmed, and an empty optional is stored as nil.
- Must not: touch SwiftUI, or be called off the main actor.

### `LibraryError`
`LocalizedError` with cases `emptyTitle`, `invalidISBN`, `emptyCollectionName`, `duplicateCollectionName`, `finishBeforeStart`, `noOpenReading`, `readingAlreadyOpen`, `saveFailed(underlying)`. Localized `errorDescription`, for example "A collection with this name already exists." / "Eine Sammlung mit diesem Namen gibt es schon.".

### `ISBN` (Logic)
- `ISBN.parse(_ text: String) -> ISBNCheck`, with results `.empty`, `.incomplete`, `.valid(ISBN)` and `.invalid`.
- It strips spaces and hyphens, accepts ISBN-10 (X as the last character, either case) and ISBN-13 (978/979), and checks the checksum.
- `ISBN.isbn13` converts ISBN-10 to 13.
- Pure and `Sendable`.

### `AuthorName` (Logic)
- `normalize(_:)` collapses whitespace. `matchKey(_:)` folds the name.
- `guessSortName(_:)`:
  - One word stays as it is ("Homer").
  - Otherwise the last word is the surname. Lowercase particles directly before it (von, van, de, der, den, du, da, di, del, della, des, la, le, zu, zum, zur, vom, ten, ter) move behind the given names: "Johann Wolfgang von Goethe" → "Goethe, Johann Wolfgang von", "Thomas Mann" → "Mann, Thomas".
  - Capitalized particles ("Le Guin") are not recognized. The user corrects those.

### `TextFolding` (Logic)
- `fold(_:)` folds case and diacritics with the de_DE locale.
- `compare(_:_:)` does de_DE collation, case- and diacritic-insensitive, numeric.
- `titleSortKey(_:)` drops one leading article (Der, Die, Das, The, A, An, case-insensitive) when more words follow.

### `SortField`, `SortDirection`, `SortLevel`, `SortLevels`, `BookSorter` (Logic)
- `SortField` cases and names:

  | Field | Short name (toolbar) | Long name (popover) |
  |---|---|---|
  | `author` | Author / Autor | Author |
  | `title` | Title / Titel | Title |
  | `year` | Year / Jahr | Year Published / Erscheinungsjahr |
  | `dateAdded` | Added / Hinzugefügt | Date Added |
  | `dateStarted` | Started / Begonnen | Date Started |
  | `dateFinished` | Finished / Beendet | Date Finished |
  | `rating` | Rating / Bewertung | Rating |
  | `pages` | Pages / Seiten | Pages |

  Each field has its direction names: A to Z / A bis Z, Z to A / Z bis A, Oldest first / Älteste zuerst, Newest first / Neueste zuerst, Lowest first / Niedrigste zuerst, Highest first / Höchste zuerst.
- `SortLevels` holds the raw string, the default, add, remove (not the first level) and `availableFields`.
- `BookSorter.sorted(_ books: [Book], by: SortLevels) -> [Book]`:
  - It precomputes one `BookSortKey` value per book: folded first-author sort name, title key, year, added date, latest start, latest finish, rating, pages.
  - A missing value sorts last in both directions.
  - Ties go to the title key, then `addedAt`, then `id`.
  - The comparator is pure, so tests run on plain `BookSortKey` values without models.

### `BookSearch` (Logic)
`matches(_ key: SearchKey, query:)`. The haystack, built once per book, is the folded title, subtitle, author names, publisher, `isbnText`, `isbn13` and reading notes. Every whitespace-separated query token must appear. "boll" matches "Böll".

### `LibraryLists` (Logic)
- `LibraryListID` is Hashable, Codable and RawRepresentable (`"all"`, `"collection:<uuid>"`), so the selected list can be persisted.
- `books(in:from:collections:)` returns a list's books. `counts(books:) -> [LibraryListID: Int]` returns all counts.
- `displayName` returns the built-in list names.

### `BookDraft`, `AuthorDraft`, `DraftStatus` (Logic)
- `BookDraft` is a value type covering every field of the Add/Edit sheet:
  - `authors: [AuthorDraft]`, where each `AuthorDraft` has a name and a sort name and is either existing or guessed
  - `isbnText`, `coverData`
  - `status: DraftStatus?` (nil for a book without readings or with an abandoned current reading)
  - `startedAt`, `finishedAt`, `rating`, `notes`
  - `collectionIDs: [UUID]`
- `BookDraft(book:)` fills it for Edit.
- `issues: Set<DraftIssue>` returns `emptyTitle`, `invalidISBN`, `invalidYear`, `invalidPages`. `canSave` is true when there are no issues.
- No model access except the `init(book:)` reader.

### `DuplicateIndex` (Logic)
- Built from all books except the one being edited.
- `match(for draft:) -> Book?` uses ISBN-13 first, then the folded title plus any folded author name.
- `DuplicateIndex.label(for:)` returns "Der Zauberberg (1924)", or the title alone when there is no year.

### `CoverImage` and `CoverPalette` (Logic)
- `@concurrent static func normalize(_ data: Data) async throws -> Data` (directional) uses ImageIO, longest side 1200 px, JPEG 0.85. Images that ImageIO cannot read throw `CoverImageError.unreadable`.
- `CoverPalette.colors: [UInt32]`, the 11 hex values. `CoverPalette.index(for: UUID) -> Int` uses FNV-1a.
- Must not import SwiftUI or AppKit.

### `BookFormatting` (Logic)
- Takes an explicit `Locale`, which keeps it testable:
  - `metaLine(book)` → "1901 · 759 pages · German · ISBN …" (year without grouping, pages via the plural key "%lld pages")
  - `statusLine(reading)` → "Started 3 Oct 2026", "Finished 2 Mar 2019", "Abandoned 5 Nov 2026"
  - `badge(reading)` → "Reading since 3 Oct 2026", "Finished 2 Mar 2019", "Abandoned", "Want to Read"
  - `readingSummary(reading)` → "Reading · Started 3 Oct 2026", "Finished · 12 Jan – 2 Mar 2019"
  - `bookCount(n)` → "No books" for 0, otherwise the plural key "%lld books"
  - `sortButtonLabel(levels)` → "Sort: Author, Year"
- Every sentence is a catalog key with placeholders, never concatenated.

### `BuchhalterApp` (Buchhalter/App)
- `@main`. It builds the container with `LibraryContainer.make(at: LibraryLocation…)` and, on failure, shows an alert and quits (Decision 25).
- It has one `Window("Buchhalter", id: "main")` with `RootView`, `.modelContainer(container)`, `.tint(Theme.accent)`, and `.commands { LibraryCommands; BookCommands }`.

### `WindowModel` (App, `@Observable @MainActor`)
- `selectedList: LibraryListID`, persisted through `@AppStorage("selectedList")` and defaulting to `.all`.
- `selectedBookID: PersistentIdentifier?`, `searchText`, `isSearchFocused`.
- `sheet: ActiveSheet?`: `.addBook`, `.editBook(id)`, `.finish(id)`, `.abandon(id)`, `.editReading(id)`, `.newCollection(addingBook: id?)`.
- `pendingDelete: PersistentIdentifier?`, `renamingCollectionID`, `isCreatingCollection`, `gridPath` (the NavigationStack path in grid mode).
- Published to the commands through `focusedSceneValue`.
- Must not hold model objects across changes: it keeps ids only.

### `RootView` (Views)
- `@Query` books, readings (only to drive refreshes), collections sorted by `sortIndex`, and list settings.
- It computes the list's books (`LibraryLists`), filters them (`BookSearch`) and sorts them (`BookSorter`) in core.
- It chooses the three-column or two-column `NavigationSplitView` from the list's `ViewMode`.
- It builds `Library(context:undoManager:)` and passes it down through `\.library`. It does not set `modelContext.undoManager`.
- It hosts the sheets and the delete confirmation.

### Other views
- **`SidebarView` and `CollectionRow`:**
  - The Library and Collections sections show icons and counts.
  - The hint "Group books your way, like "Read in 2026"." appears while there are no collections.
  - `New Collection` at the bottom adds an inline name field.
  - Rows support `.onMove`, `.dropDestination(for: BookDragItem.self)`, and a context menu with `Rename` and `Delete Collection…` (confirmation).
  - The name error shows at the field.
- **`LibraryToolbar`:** list title plus `navigationSubtitle` count (Mac-only modifier file), the Sort button with `SortPopover`, a segmented List/Grid picker, `.searchable(placement: .toolbar)` with `.searchFocused`, and `+`.
- **`SortPopover`:** "Sort <list name>", `Reset to Default`, one row per level (field popup, direction popup, − button; the first level's button is disabled), `+ Add Level` (disabled when all fields are used), and the footnote.
- **`BookListView` and `BookRow`:** a `List` with selection, the row cover at 40×58, title in serif 15 semibold, author, status line, `.draggable`, `.contextMenu(BookContextMenu)`, `.onDeleteCommand`.
- **`BookGridView` and `BookGridCell`:** `LazyVGrid` with adaptive columns (six at the design width of about 870 pt). Each cell has a 2:3 cover, title, author, and stars or "No rating". Context menu and drag as in the list. Double-click or `Open` pushes the detail.
- **`BookContextMenu`:**
  - `Open`
  - an `Add to Collection` submenu with ticks; choosing a ticked collection removes the book; it ends with `New Collection…`
  - `Remove from "<name>"`, only in a collection
  - `Delete Book…`
- **`EmptyLibraryView`:** "Your library is empty", the sub-line, the `Add Book…` button, "or press ⌘N". **`NoMatchesView`:** "No books match "…"".
- **`BookDetailView`:**
  - the large cover (120×180) with a drop target and a context-menu item "Remove Cover Image"
  - title (serif 28), subtitle, authors, meta line, `StatusBadge`
  - status buttons: Finish Reading… (primary), Abandon, Read Again, Edit
  - `CollectionChips` with `+ Add to Collection` (a menu of collections)
  - `ReadingsSection` (double-click opens Edit Reading)
- **`BookEditorSheet`:**
  - Used for Add Book and Edit Book. It owns a `BookDraft` in `@State` and runs `ISBN.parse` and `DuplicateIndex` live.
  - The status segmented control has inline fields per status.
  - Collection chips have `+ Add`.
  - The buttons are Cancel and Add Book or Save.
  - Sub-views:
    - `AuthorField`: chips plus the "Add author" field, and one "Sorted as: …" line with `Edit` per author
    - `CoverPicker`: preview, drop area, `Choose File…` with `.fileImporter`, paste through a Mac-only modifier on the focusable drop area, `Remove Image`
- **Small sheets:**
  - `FinishReadingSheet`: Started read-only, Finished date picker limited to on or after the start, `StarRatingControl` with Clear, Notes, Cancel and Finish
  - `AbandonSheet`: a toggle plus date (default today), note, Cancel and `abandonSheet.confirm`
  - `EditReadingSheet`: dates, rating, notes, Cancel, Save, `Delete Reading`
  - `NewCollectionSheet`: used from the book menu
- **Common views:** `CoverView` (the image or `GeneratedCoverView`, serif title and author on the palette colour), `StarRatingView` and `StarRatingControl` (accessibility labels "Rated 4 of 5" and "%lld stars" through plurals), `Chip`, `Theme`.
- **Views must not:** set model properties, compute membership or sort order, or format dates and counts by hand.

### Mac-only files (Buchhalter/Mac)
- `AppDelegate`: quits after the last window closes. (Saving after undo is done by `Library`'s own undo closures.)
- `LibraryCommands`: ⌘N Add Book…, ⌘F Find.
- `BookCommands`: the Book menu ("Book" / "Buch") with Edit Book…, Finish Reading…, Abandon…, Read Again, Add to Collection ›, Delete Book… ⌘⌫, enabled from the focused book.
- `CoverPasteModifier`: `.onPasteCommand`.
- `MacToolbarModifiers`: `navigationSubtitle`.

## Interactions

All flows run on the main actor except `CoverImage.normalize`. State lives in SwiftData (main context) and `WindowModel` (ids and UI state).

**Launch**
1. `BuchhalterApp.init` calls `LibraryLocation.resolve(ProcessInfo.environment)` and logs `library: <path>`.
2. `LibraryContainer.make` builds the container. On failure: alert, quit, file untouched.
3. `RootView` builds `Library` with the window's `undoManager` (the context's own `undoManager` stays `nil`).
4. The `@Query` results feed `LibraryLists.counts` (sidebar) and the selected list from `@AppStorage`, falling back to `.all`.
5. With 0 books, the content shows `EmptyLibraryView`, the toolbar shows "No books", and the sidebar shows the hint.

**Show a list**

```
@Query books ─► LibraryLists.books(in: selectedList)
            ─► BookSearch.matches(searchText) (if not empty)
            ─► BookSorter.sorted(by: ListSettingsOperations.settings(for: list).levels)
            ─► BookListView | BookGridView (by ViewMode)
```

Any model change (including undo) re-runs `@Query` and observation, so the list and counts update.

**Add Book (⌘N, `+`, `Add Book…`)**
1. `WindowModel.sheet = .addBook`. `BookEditorSheet` creates an empty `BookDraft` (language from the latest book) and a `DuplicateIndex`.
2. Typing updates the draft:
   - `ISBN.parse` sets the border and message.
   - Adding an author chip calls `Library.resolveAuthors` in read-only lookup mode: an existing author's sort name, or `AuthorName.guessSortName`.
   - `DuplicateIndex.match` shows the banner.
3. Cover drop, paste or file: data → `await CoverImage.normalize` (off main) → back on main into `draft.coverData`. An error shows "This image can't be used." under the drop area.
4. `Add Book` (or `Add Anyway`) runs `Library.addBook(draft)` inside `change("Add Book")`. In that one group it:
   - inserts the Book
   - links or creates Authors, writes edited sort names, creates Authorships with positions
   - creates one Reading from the status
   - adds the book to its collections
   - saves

   Then the sheet closes, `selectedBookID` is set to the new book, and the list switches to All Books when the current list does not contain it.
5. `Show Book` closes the sheet and selects the existing book (switching to All Books if needed). Cancel discards the draft.

**Edit Book.** The same sheet with `BookDraft(book:)`, and `DuplicateIndex` excluding the book. `Save` calls `Library.updateBook(book, with: draft)` in one group: fields, authorships rebuilt in the new order, sort names, `applyStatus`, collection diff, cover.

**Finish, Abandon, Read Again, edit or delete a reading.** The buttons in `BookDetailView` set the sheet (or call `readAgain` directly). The sheet's confirm button calls the matching `ReadingOperations` method in one undo group. The book moves between lists through the derived current reading. Double-clicking a row in `ReadingsSection` opens `EditReadingSheet`, whose `Delete Reading` calls `deleteReading`.

**Cover on the detail pane.** A drop runs `normalize`, then `Library.setCover(data, for: book)` (undoable, "Change Cover"). "Remove Cover Image" calls `setCover(nil…)`.

**Collections**
- `New Collection`: an inline field. On submit, `validateCollectionName` runs. An error stays at the field and nothing is created. A valid name calls `createCollection` (undo "New Collection"). Esc cancels.
- Rename works the same way inline.
- Reorder: `.onMove` → `moveCollections`.
- Delete: confirmation → `deleteCollection` (the cascade removes its `ListSettings`; books stay).
- Dropping a `BookDragItem` on a row: look up the book by UUID, then `add(book, to:)`.
- The context menu's `Add to Collection ›` calls `toggle`. `New Collection…` opens `NewCollectionSheet`, which calls `createCollection(named:adding:)`.

**Sorting and view mode.** The popover edits a local `SortLevels` and calls `setSortLevels(_:for:)` on each change. The view picker calls `setViewMode`. Both run without undo, are saved immediately and persist per list.

**Search.** `⌘F` sets `isSearchFocused`. Typing updates `searchText`, and the list is recomputed. Esc clears the native field. No matches shows `NoMatchesView(searchText)`. The search text is not persisted.

**Delete Book.** ⌫ (`.onDeleteCommand`), the context menu or the Book menu sets `pendingDelete`. The confirmation dialog then calls `Library.deleteBook` (one group, cascade) and clears the selection.

**Undo and redo.** ⌘Z/⇧⌘Z go to the window's undo manager. The step `Library.change` registered applies its diff, saves, and registers the inverse. `@Query` refreshes because the context saved real changes, and a quit right after ⌘Z persists.

**Language.** SwiftUI and AppKit pick `de` from the main bundle's `de.lproj`. `BookFormatting` uses `Locale.current`, and SwiftUI views pass `@Environment(\.locale)`.

## Changes by file

| File | New/changed | What |
|---|---|---|
| `Package.swift` | new | tools 6.2, platforms macOS 27 and iOS 27, targets `BuchhalterCore`, `Buchhalter` (product `buchhalter`, AppKit linked, `defaultIsolation(MainActor.self)`), `BuchhalterCoreTests`; no resources |
| `Makefile` | new | `build`, `app` (copy binary to `Contents/MacOS/Buchhalter`, Info.plist, `xcstringstool compile` into `Contents/Resources`, `codesign --force --sign -`, `lsregister -f`), `install`, `test`, `strings` (extract + sync), `clean`; rebuild only on changes, as in swell |
| `Resources/Info.plist` | new | `CFBundleIdentifier local.buchhalter`, `CFBundleExecutable Buchhalter`, `CFBundleName Buchhalter`, `CFBundlePackageType APPL`, `LSMinimumSystemVersion 27.0`, `CFBundleDevelopmentRegion en`, `CFBundleLocalizations [en, de]`, `NSPrincipalClass NSApplication`, version 0.1 (1), `UTExportedTypeDeclarations` for `local.buchhalter.book` |
| `Resources/Localizable.xcstrings` | new | every UI and core text, English and German, plural variants for books, pages and stars |
| `.gitignore` | unchanged | already ignores `.build/` and `build/` (the scratch library under `build/` is covered) |
| `Sources/BuchhalterCore/Model/SchemaV1.swift` | new | the six `@Model` types nested in SchemaV1 |
| `Sources/BuchhalterCore/Model/ModelTypes.swift` | new | top-level typealiases |
| `Sources/BuchhalterCore/Model/LibraryMigrationPlan.swift` | new | migration plan with SchemaV1 |
| `Sources/BuchhalterCore/Model/Enums.swift` | new | `ReadingStatus`, `BookOrigin`, `ViewMode` with display names |
| `Sources/BuchhalterCore/Model/Book+Derived.swift` | new | current reading, ordered authors, derived dates and rating |
| `Sources/BuchhalterCore/Store/LibraryLocation.swift` | new | `BUCHHALTER_HOME` / Application Support resolution |
| `Sources/BuchhalterCore/Store/LibraryContainer.swift` | new | on-disk and in-memory containers |
| `Sources/BuchhalterCore/Store/Library.swift` | new | `Library` struct, `change`/`withoutUndo` helpers, undo registration |
| `Sources/BuchhalterCore/Store/LibrarySnapshot.swift` | new | value records, snapshot capture, diff, `apply` for undo and redo |
| `Sources/BuchhalterCore/Store/BookOperations.swift` | new | add, update, delete book, cover, sort name, author resolution |
| `Sources/BuchhalterCore/Store/ReadingOperations.swift` | new | finish, abandon, read again, update, delete reading, apply status |
| `Sources/BuchhalterCore/Store/CollectionOperations.swift` | new | create, validate, rename, delete, move, add, remove, toggle |
| `Sources/BuchhalterCore/Store/ListSettingsOperations.swift` | new | sort levels and view mode per list, no undo |
| `Sources/BuchhalterCore/Store/LibraryError.swift` | new | localized errors |
| `Sources/BuchhalterCore/Logic/ISBN.swift` | new | parse, checksum, ISBN-10 → 13 |
| `Sources/BuchhalterCore/Logic/AuthorName.swift` | new | normalize, match key, sort-name guess |
| `Sources/BuchhalterCore/Logic/TextFolding.swift` | new | folding, de_DE collation, title article key |
| `Sources/BuchhalterCore/Logic/BookSort.swift` | new | `SortField`, `SortDirection`, `SortLevels`, `BookSortKey`, `BookSorter` |
| `Sources/BuchhalterCore/Logic/BookSearch.swift` | new | search key and matching |
| `Sources/BuchhalterCore/Logic/LibraryLists.swift` | new | `LibraryListID`, membership, counts |
| `Sources/BuchhalterCore/Logic/BookDraft.swift` | new | draft, author draft, validation, init from book |
| `Sources/BuchhalterCore/Logic/DuplicateIndex.swift` | new | duplicate matching and label |
| `Sources/BuchhalterCore/Logic/CoverImage.swift` | new | ImageIO normalize |
| `Sources/BuchhalterCore/Logic/CoverPalette.swift` | new | 11 colours, FNV-1a index |
| `Sources/BuchhalterCore/Logic/BookFormatting.swift` | new | status lines, badge, meta line, counts, sort label |
| `Sources/Buchhalter/App/BuchhalterApp.swift` | new | `@main`, container, Window scene, commands |
| `Sources/Buchhalter/App/WindowModel.swift` | new | selection, sheets, search, pending delete |
| `Sources/Buchhalter/Views/RootView.swift` | new | split-view switch, queries, undo wiring, sheets |
| `Sources/Buchhalter/Views/Sidebar/SidebarView.swift` | new | sections, counts, hint, New Collection |
| `Sources/Buchhalter/Views/Sidebar/CollectionRow.swift` | new | inline name, drop target, context menu |
| `Sources/Buchhalter/Views/Toolbar/LibraryToolbar.swift` | new | title, sort button, view picker, search, `+` |
| `Sources/Buchhalter/Views/Toolbar/SortPopover.swift` | new | level editor |
| `Sources/Buchhalter/Views/Books/BookListView.swift` | new | list, selection, delete command |
| `Sources/Buchhalter/Views/Books/BookRow.swift` | new | row layout |
| `Sources/Buchhalter/Views/Books/BookGridView.swift` | new | grid and detail push |
| `Sources/Buchhalter/Views/Books/BookGridCell.swift` | new | cell layout, rating or "No rating" |
| `Sources/Buchhalter/Views/Books/BookContextMenu.swift` | new | Open, Add to Collection ›, Remove from, Delete |
| `Sources/Buchhalter/Views/Books/EmptyStates.swift` | new | empty library, no matches |
| `Sources/Buchhalter/Views/Detail/BookDetailView.swift` | new | detail layout, actions, cover drop |
| `Sources/Buchhalter/Views/Detail/StatusBadge.swift` | new | badge |
| `Sources/Buchhalter/Views/Detail/ReadingsSection.swift` | new | readings list, double-click |
| `Sources/Buchhalter/Views/Detail/CollectionChips.swift` | new | chips and `+ Add to Collection` |
| `Sources/Buchhalter/Views/Sheets/BookEditorSheet.swift` | new | Add/Edit Book |
| `Sources/Buchhalter/Views/Sheets/AuthorField.swift` | new | author chips, "Sorted as", Edit |
| `Sources/Buchhalter/Views/Sheets/CoverPicker.swift` | new | preview, drop, file importer, remove |
| `Sources/Buchhalter/Views/Sheets/FinishReadingSheet.swift` | new | Finish Reading |
| `Sources/Buchhalter/Views/Sheets/AbandonSheet.swift` | new | Abandon |
| `Sources/Buchhalter/Views/Sheets/EditReadingSheet.swift` | new | edit or delete a reading |
| `Sources/Buchhalter/Views/Sheets/NewCollectionSheet.swift` | new | name sheet for the book menu |
| `Sources/Buchhalter/Views/Common/CoverView.swift` | new | image or generated cover |
| `Sources/Buchhalter/Views/Common/StarRating.swift` | new | display and control |
| `Sources/Buchhalter/Views/Common/Chip.swift` | new | chip style |
| `Sources/Buchhalter/Views/Common/Theme.swift` | new | accent, tints, error colour, palette mapping, serif fonts |
| `Sources/Buchhalter/Views/Common/BookDragItem.swift` | new | Transferable with `local.buchhalter.book` |
| `Sources/Buchhalter/Mac/AppDelegate.swift` | new | quit on close |
| `Sources/Buchhalter/Mac/LibraryCommands.swift` | new | ⌘N, ⌘F |
| `Sources/Buchhalter/Mac/BookCommands.swift` | new | Book menu |
| `Sources/Buchhalter/Mac/CoverPasteModifier.swift` | new | `onPasteCommand` for images |
| `Sources/Buchhalter/Mac/MacToolbarModifiers.swift` | new | `navigationSubtitle` |
| `Tests/BuchhalterCoreTests/*.swift` | new | see Testing |
| `docs/dev/architecture.md` | changed | Targets and Layout (no per-target catalogs, top-level `Resources/Localizable.xcstrings`); Data model (Authorship, ListSettings, `isbn13`/`isbnText`, `endedAt`, origin, no lookup ids yet); Localization (main-bundle catalog, `make strings`); Data flow (in-memory filter, sort and search, undo grouping); UI structure (grid two-column); Build table (`make strings`, `open --env`); new Decisions 10–14 from this plan; remove "Direction" marks where code now exists |
| `AGENTS.md` | changed | Quick facts: Status "Library feature: books, readings, collections, sort, search, undo"; Run `open --env BUCHHALTER_HOME=… build/Buchhalter.app` for tests, `open build/Buchhalter.app` for the real library; add `make strings` |
| `README.md` | changed | Status line |

## Testing

**Unit tests** (Swift Testing, `@MainActor` where models are involved, in-memory containers only):

1. `ISBNTests`:
   - valid ISBN-10 (with X), ISBN-10 and ISBN-13, with and without hyphens or spaces
   - wrong check digit gives invalid
   - short input gives incomplete
   - ISBN-10 → 13 conversion
   - `978-3-10-048431-7` is invalid, matching the design
2. `AuthorNameTests`: Thomas Mann, Johann Wolfgang von Goethe, Homer, Ludwig van Beethoven, extra whitespace; the match key folds case and accents.
3. `TextFoldingTests`: "Ärger" sorts among the A names; case and accent folding; "Der Zauberberg" keys under Z; "A" alone stays; "The Hours" → "Hours".
4. `BookSortTests`:
   - the default levels
   - every field in both directions
   - nil values last in both directions, books without an author last
   - the title tiebreak
   - the spec's Read in 2026 example order (Eliot, Fontane, Grass, Hesse, Johnson, Mann, Nabokov, Sebald, Tolstoy, Williams, Woolf)
   - raw string round trip, unknown fields skipped, the first level not removable, no duplicate fields
5. `BookSearchTests`: "boll" finds Böll; matches in title, subtitle, author, publisher, ISBN with and without hyphens, and notes; multi-token AND.
6. `LibraryListsTests`: membership for all four built-in lists plus collections; abandoned only in All Books and collections; a book without readings; counts.
7. `BookDraftTests`: empty title, invalid ISBN, an empty ISBN passes, year and pages validation, round trip from a book.
8. `DuplicateIndexTests`: ISBN-10 versus ISBN-13 of the same book, title plus author, title with a different author is no match, Edit excludes itself, the label.
9. `BookOperationsTests`:
   - add with each status creates the right reading
   - authors reused across books, order kept
   - a sort-name change affects all books
   - update rebuilds authorships
   - delete cascades readings and keeps authors and collections
   - set and remove cover
10. `ReadingOperationsTests`:
    - finish needs only a date and refuses a finish before the start
    - abandon with and without a date
    - read again creates a second reading, not a second book, and is refused while a reading is open
    - apply status (Want to Read → Reading in place; Finished → Reading creates a new reading)
    - update and delete a reading, including the last one
11. `CollectionOperationsTests`: empty and duplicate names refused (case- and accent-folded); rename; move renumbers; delete keeps books and removes settings; toggle; create-and-add.
12. `ListSettingsTests`: default when missing; per list and per collection; newest `updatedAt` wins over a duplicate; view mode; reset.
13. `UndoTests` (an `UndoManager` with `groupsByEvent = false`; the context's own `undoManager` is `nil`):
    - add, edit, finish, abandon, read again, delete book (cascade, with authors, readings and collections), edit and delete reading, cover, sort name, and every collection change each undo and redo as one step. The state is read with a fresh fetch.
    - a deleted collection comes back with its list settings
    - sort and view changes leave the undo stack untouched
    `UndoPersistenceTests`: rename a collection, edit a book, finish a reading, abandon a reading, set a cover and delete a book. After the action, after undo, after redo and after a second undo, the value is checked from a fresh fetch on the main context and from a second `ModelContext` on the same container.
14. `PersistenceTests`: an on-disk container in `FileManager.default.temporaryDirectory/<UUID>`. Books, readings, collections, covers and list settings are written, the container is reopened, and everything is read back. The folder is removed after the test. The test never touches Application Support.
15. `LibraryLocationTests`: `BUCHHALTER_HOME` set, empty and unset (a passed environment dictionary, no real folder created outside the temp folder).
16. `CoverImageTests`: a 3000×2000 PNG made in the test (CoreGraphics, ImageIO) normalizes to a longest side of 1200 as JPEG; unreadable data throws. `CoverPaletteTests`: the same UUID gives the same index; the index is within range.
17. `BookFormattingTests`: with `Locale(identifier: "en_GB")` and `"de_DE"`, the day–month–year output is "3 Oct 2026" / "3. Okt. 2026", the range output is "12 Jan – 2 Mar 2019" / "12. Jan. – 2. März 2019", and year 1901 prints without grouping. These test the format styles only, since catalog sentences fall back to English in tests.
18. `LocalizationCatalogTests`: reads `Resources/Localizable.xcstrings` through `#filePath`. It fails if any key lacks an `en` or `de` value, if any `de` value is in state `new` or `needs_review`, or if a plural key lacks `one`/`other` in both languages. It also checks that the spec's German terms table appears exactly: Bibliothek, Lese ich, Will ich lesen, Gelesen, Alle Bücher, Sammlungen, Neue Sammlung, Lektüren, Fertig gelesen…, Abbrechen, Nicht zu Ende gelesen, Bearbeiten, Zu Sammlung hinzufügen, Sortieren, Suchen, and `abandonSheet.confirm` → Lektüre abbrechen.

**Commands**

- `swift build`
- `swift test`
- `make strings` (then `swift test` again for the catalog test)
- `make app`
- The agent starts the app with:
  ```
  BUCHHALTER_HOME=/Users/juergen/dev/buchhalter/build/scratch-library build/Buchhalter.app/Contents/MacOS/Buchhalter 2> /Users/juergen/dev/buchhalter/build/run.log
  ```
  In the background, then read the log after the user quits. For German, append `-AppleLanguages '(de)' -AppleLocale de_DE`.

**Manual checks for the user.** Always use the scratch library. Remove `build/scratch-library` before check 3 for a true first launch (this deletes only test data in the build folder). The English run is:

```
open --env BUCHHALTER_HOME=/Users/juergen/dev/buchhalter/build/scratch-library build/Buchhalter.app
```

1. `make app` finishes and `build/Buchhalter.app` exists. The `open --env …` command above starts it. (`swift test` passes, run by the agent.)
2. `run.log` (or Console) shows `library: /Users/juergen/dev/buchhalter/build/scratch-library/library.store`.
3. First launch: All Books is selected, the toolbar says "No books", all four counts are 0, the Collections hint shows, and the centre shows "Your library is empty", `Add Book…` and "or press ⌘N".
4. ⌘N, the toolbar `+` and `Add Book…` each open the sheet. Add "Buddenbrooks" (Thomas Mann, Want to Read), "Stoner" (John Williams, Reading) and "Der Zauberberg" (Thomas Mann, Read, rating 4, a note). Each appears in its list and in All Books, and the counts change at once.
5. An author "Thomas Mann" shows "Sorted as: Mann, Thomas". "Johann Wolfgang von Goethe" shows "Goethe, Johann Wolfgang von". Change Thomas Mann's sort name to "Zzz, Thomas": both Mann books move to the end of All Books (Author A to Z). Undo.
6. ISBN `978-3-10-048431-7` gives a red border, "This ISBN is not valid. Check the last digit." and a disabled `Add Book`. Valid values pass: `978-3-596-29431-2`, `9783596294312`, `3-596-29431-2` (an ISBN-10 with hyphens, the same book) and `0 8044 2957 X` (an ISBN-10 ending in X). The check digit of the Buddenbrooks ISBN is 2: `978-3-596-29431-3`, which the design's detail pane shows as text, fails the checksum and is rejected. In Edit Book, an invalid ISBN disables `Save`.
7. Add "Der Zauberberg" by Thomas Mann again: "Already in your library: Der Zauberberg (1924)" appears. `Show Book` selects the existing one. Repeat, then use `Add Anyway`: a second book exists. Repeat with only a matching ISBN.
8. Covers:
   - Drop an image file onto the Add Book drop area.
   - Copy an image in Preview and press ⌘V on the focused drop area.
   - Use `Choose File…`.
   - In Edit Book, replace the cover.
   - Drop an image onto the detail pane's large cover.
   - Remove a cover: the generated cover returns.
   - Books without an image show a coloured generated cover, and a book keeps its colour after a relaunch.
9. On Stoner: `Finish Reading…` shows Started read-only. Only Finished is needed. The book moves from Reading to Read. `Abandon` on another reading book removes it from Reading, and All Books shows "Abandoned". `Read Again` on Der Zauberberg moves it to Reading with today's start. All Books still has one Der Zauberberg, and its Readings section lists both readings.
10. Double-click a reading: it opens for editing, and `Save` changes it. `Delete Reading` removes it.
11. Collections:
    - Create "Read in 2026" and "Owned".
    - An empty name and "read in 2026" are refused with an error at the field.
    - Rename one, drag to reorder, and delete one after confirming: its books remain.
    - Add books by dragging from the list and from the grid onto a collection, through the Add/Edit Book chips, through `+ Add to Collection`, and through the context menu's `Add to Collection ›`, which ticks the current collections. Choosing a ticked one removes the book.
    - `Remove from "Read in 2026"` appears only inside that collection.
12. Sorting:
    - Every list starts with "Sort: Author, Year".
    - In Reading, set Title A to Z and add Pages. In a collection, set Rating Highest first and switch it to grid. Quit and relaunch: each list keeps its own order and view.
    - `Reset to Default` restores Author A to Z, then Year Published oldest first.
    - The popover title reads "Sort Reading", and the first level has no active − button.
13. Sorting by Title puts "Der Zauberberg" among the Z titles. Add an author "Ärger" (sorted as "Ärger"): with Author sorting it is among the A names. A book without an author, and books without pages under Pages sorting, come last in both directions.
14. Search: "boll" finds a book by "Heinrich Böll". ⌘F focuses the field and Esc clears it. "xyz" shows "No books match "xyz"".
15. Delete Book: ⌫ with a book selected, `Delete Book…` in the context menu and in the Book menu each ask for confirmation, then the book and its readings disappear. ⌘Z brings everything back and ⇧⌘Z removes it again. Then check that ⌘Z undoes one each of: add, edit, finish, abandon, read again, reading edit, reading delete, collection create, rename, reorder, delete, add book, remove book. Edit → Undo names the action.
16. Quit, relaunch with the same `open --env …`: books, readings, collections, covers, sort choices and view choices are all there.
17. German:
    ```
    open --env BUCHHALTER_HOME=/Users/juergen/dev/buchhalter/build/scratch-library build/Buchhalter.app --args -AppleLanguages '(de)' -AppleLocale de_DE
    ```
    Every label, button, status, menu (including the system Edit and Window menus), placeholder, alert and empty state is in German. Dates read "3. Okt. 2026", counts "1 Buch" and "2 Bücher", pages "759 Seiten", the sort button "Sortieren: Autor, Jahr". The Abandon sheet's buttons are `Abbrechen` and `Lektüre abbrechen`. Repeat checks 3, 4, 9, 11, 12 and 14 briefly in German. Also once with only `-AppleLanguages '(de)'`, to see the date format with the user's own region.
18. Optional, the user's choice: `open build/Buchhalter.app` without `--env` starts on the real library in `~/Library/Application Support/Buchhalter/`. This creates the real store, so it is not part of the test runs.

## Permissions

| Action | Status |
|---|---|
| Editing and creating repo files | normal editing |
| `swift build`, `swift test` | allowed (`Bash(swift build:*)`, `Bash(swift test:*)` in `.claude/settings.json`) |
| `make app`, `make test`, `make strings`, `make clean`, and the `codesign --force --sign -` and `lsregister -f` they run | allowed (`Bash(make:*)`) |
| `make install` (replaces `/Applications/Buchhalter.app`) | allowed by `Bash(make:*)`, but **only on the user's request**. It overwrites an installed copy |
| `xcrun xcstringstool …` directly (for example `compile --dry-run`, `--help`) | allowed (`Bash(xcrun xcstringstool:*)`) |
| Starting the app: `BUCHHALTER_HOME=/Users/juergen/dev/buchhalter/build/scratch-library build/Buchhalter.app/Contents/MacOS/Buchhalter …` in the background | allowed (`Bash(BUCHHALTER_HOME=*)`) |
| `open --env … build/Buchhalter.app` or `open build/Buchhalter.app` | not allowed, prompts. These are meant for the user at the screen |
| `rm -rf build/scratch-library` before a first-launch check | prompts. It deletes scratch test data only, and the user confirms |
| git commits | not done unless the user asks. One `feat: Add library` commit on `main`, with no `Co-Authored-By` line (AGENTS.md wins over the session's attribution reminder). No push |
| Network | none needed |

## Risks and open points

- **Irreversible schema step.** The first launch against the real library fixes SchemaV1 in practice. From then on, any shape change needs SchemaV2 and a migration stage. Settle the model through the scratch library first, and launch on the real library only once the user accepts the feature.
- **The `make install` step and the real library** are destructive or real-data actions. Neither is part of the implementation run.
- **Own undo.** Built because SwiftData's undo does not persist attribute changes on macOS 27.2 (Research 1). The risks are now ours: a record type that misses a field loses that field on undo, so a new field on a model must be added to its record in `LibrarySnapshot.swift` and to `apply`. `UndoTests` and `UndoPersistenceTests` cover the current fields. Snapshots are linear in the number of books per action.
- **Sort and view changes** are saved without any undo registration (`withoutUndo`). Because `Library` registers only what `change` captured, settings never reach the undo stack. A collection's settings are part of its record, so deleting and undoing a collection restores them.
- **`@Query` refresh on reading-only changes.** The root queries `Reading` as well, so status changes refresh lists and counts. Check this in manual check 9.
- **`xcstringstool compile` output and the English `.lproj`.** Verify with `--dry-run` that `en.lproj` is written, including the stringsdict for plurals. If English plurals are missing, compile with `--language en --language de` explicitly.
- **`make strings` needs a compile.** It builds into `build/strings-build` with `-emit-localized-strings`, so it takes a few seconds and sees exactly what the compiler sees. Keys the compiler cannot see (a `LocalizedStringResource` stored in a variable, as in the sort field names) are missed unless the literal is at a call site. The rule is that every key is a literal at its call site.
- **The sort label list format.** Check that `.list(type: .unit, width: .short)` gives "Author, Year" / "Autor, Jahr". If not, use the catalog key "%@, %@" pattern per level count (up to 8), never a hand-joined string.
- **Region versus language.** "3 Oct 2026" needs an English language with a non-US region. On en_US the format is "Oct 3, 2026", which is correct locale behaviour, not a bug. The German checks pass `-AppleLocale de_DE` so they match the spec's examples.
- **Sidebar `.onMove` and `.dropDestination` on the same rows** can interfere on macOS. If reordering breaks the book drop, move the book drop to `.onInsert(of: [.buchhalterBook])` on the `ForEach`.
- **Paste needs focus.** ⌘V in the sheet pastes into the focused text field. Paste works on the drop area after clicking it (it shows a focus ring). If the user expects paste anywhere in the sheet, add a sheet-level paste handler that acts only when the pasteboard holds an image and no text field is focused.
- **Dark mode** is not designed. Custom tints keep their light values and system colours adapt. That is left for a later design pass.
- **App icon** is not part of this spec. The bundle has no `.icns`, so macOS shows the generic icon.
- **Left to the implementer:** the exact German wording for texts the spec does not give (row status lines such as "Begonnen am …", "Gelesen am …", "Abgebrochen am …"; error messages; menu items). The catalog test enforces that they exist, and the user reviews them in manual check 17.
