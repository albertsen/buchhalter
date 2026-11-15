# Architecture

Buchhalter is a SwiftUI app over a SwiftData store of books and readings. The Mac app comes first. An app for iPhone and iPad follows later: one iOS app target that runs on both. It shares the core library and most views, and the Mac and iOS apps share one library through iCloud (CloudKit).

The UI is in English and German.

This doc describes the code as it is and the direction it takes. The library feature (books, readings, collections, sort, search, undo) exists; the [Roadmap](#roadmap) lists the features that are planned but not in the first version. The architecture leaves room for them now, so they don't force a rewrite later. Each feature's plan decides the details and updates this doc when it is archived. Sections marked **Direction** describe intent, not code.

## Phases

| Phase | What | Needs |
|---|---|---|
| 1. Mac, local | macOS app, local SwiftData store, no sync. SwiftPM + `make`, ad-hoc signed, bundle id `local.buchhalter` | Nothing beyond Xcode |
| 2. iCloud sync | The same store, mirrored to a private CloudKit database | A paid Apple Developer team, a CloudKit container, a reverse-DNS bundle id under that team, an Xcode project for entitlements and provisioning |
| 3. iPhone and iPad | One iOS 27 app target (iPhone and iPad) in the same Xcode project, using `BuchhalterCore` and the shared views. Installing on the user's own devices needs the Developer team from phase 2 (a free account's installs expire after 7 days) | Phase 2 |

The features in the [Roadmap](#roadmap) are independent of the phases: book lookup and the assistant can come in phase 1 on the Mac; barcode scanning is best on iPhone and iPad.

No signing identity is installed on this Mac yet (`security find-identity -p codesigning` finds none), so phase 1 stays unsigned apart from the ad-hoc signature. The data model follows CloudKit's rules from phase 1, so turning on sync in phase 2 needs no migration of the model's shape.

## Targets

| Target | Kind | Imports | Contents |
|---|---|---|---|
| `BuchhalterCore` | library | Foundation, SwiftData, ImageIO | The `@Model` types, the versioned schemas and the migration plan, container setup (store location, in-memory for tests), `Library` with the operations that change data (add and edit a book, finish, abandon and repeat a reading, collections, list settings) and its undo, and pure logic (ISBN parsing and checking, author sort names, text folding, sorting, search, list membership, drafts, duplicate check, cover normalizing, formatting). Texts it produces (status names, sort field names, errors, sentences) come from the app's catalog. Fully unit-tested |
| `Buchhalter` | executable `buchhalter` | SwiftUI, AppKit (Mac-only files), BuchhalterCore | The Mac app: `App`, the one window, menus, views. Every declaration is `@MainActor` by default (`defaultIsolation`) |
| `BuchhalterCoreTests` | Swift Testing | BuchhalterCore | One test file per core area, against in-memory containers |

`Package.swift` uses tools version 6.2 with the Swift 6 language mode (strict concurrency) and platforms `.macOS("27.0")`, plus `.iOS("27.0")` so nothing Mac-only creeps into the core. There are no package resources and no `defaultLocalization`: the one String Catalog sits outside any target and the Makefile compiles it into the app bundle (see Localization).

When phase 2 or 3 starts, an Xcode project joins the repo. It references the local package for `BuchhalterCore`, holds the macOS app target and the iOS app target (iPhone and iPad) with their entitlements, and the views they share move into a `BuchhalterUI` library in the package. Until then the SwiftPM executable is the app, built like swell and fluff.

## Layout

```
Package.swift
Makefile
Resources/
  Info.plist            CFBundleLocalizations en, de; exported type local.buchhalter.book
  Localizable.xcstrings the one String Catalog, English and German
Sources/
  BuchhalterCore/
    Model/              @Model types in SchemaV1, migration plan, enums, derived helpers
    Store/              container, location, Library, operations, undo snapshots
    Logic/              ISBN, names, folding, sort, search, lists, draft, duplicates, covers, formatting
  Buchhalter/
    App/                App, WindowModel
    Views/              shared-ready views (no AppKit): Sidebar, Toolbar, Books, Detail, Sheets, Common
    Mac/                Mac-only code: AppDelegate, menus, paste, navigation subtitle, store failure alert
Tests/
  BuchhalterCoreTests/
docs/dev/               this doc
specs/planned/, specs/done/
```

## Data model

`SchemaV1` (Library feature). The shape below is what the code has; Conversation and ChatMessage are Roadmap.

| Type | Holds | Relationships |
|---|---|---|
| `Book` | `id`, title, subtitle, `isbn13` (normalized digits, for matching and search), `isbnText` (the user's input, for display), publisher, year, page count, language and original language (ISO 639 codes; the original only for a translation, nil when the same), cover image (external storage, JPEG, longest side 1200 px), added date, origin (`manual`, `lookup`, `scan`, `assistant`), origin note. Lookup ids come with Book lookup, as an additive optional attribute | authorships (one-to-many, cascade), readings (one-to-many, cascade), collections (many-to-many, nullify) |
| `Author` | `id`, name, sort name ("Mann, Thomas"). One per name, reused across books; kept when it has no books left | authorships (cascade) |
| `Authorship` | `id`, position. The ordered join between a book and an author: SwiftData's to-many relationships are unordered, and the first author decides the sort order | book, author |
| `Reading` | One read-through of a book: `id`, status (`wantToRead`, `reading`, `finished`, `abandoned`), started date, ended date (the finish or abandon date), rating (1–5, optional), notes, created date. The current reading of a book is the one created last | book |
| `Collection` | A user-made list of books ("Read in 2026", "Classics to Read", "Owned"): `id`, name, note, sort index, created date | books (inverse of `Book.collections`), settings (cascade) |
| `ListSettings` | The sort levels (as a string such as `author:asc,year:asc`; empty means the default) and the view mode (`list` or `grid`) of one list. `key` names a built-in list (`reading`, `wantToRead`, `read`, `all`); a collection's settings hang off the collection. No unique constraint, so readers take the newest `updatedAt` | collection |
| `Conversation` | Roadmap: one assistant chat: title, created date, provider and model used | messages (one-to-many, cascade) |
| `ChatMessage` | Roadmap: one turn: role, text, the books it added or proposed, date | conversation |

A book read twice has two readings. The sidebar's Reading, Want to Read and Read are computed from each book's current reading, not stored lists. A book without any reading is valid: it shows in All Books and its collections, without a badge. Status is optional in Add and Edit Book. Clearing it in Edit Book deletes the current reading (Want to Read, Reading or Finished); earlier readings stay, and an abandoned current reading is left alone. A translation stores its original language; the detail line shows "German (original: Japanese)". Collections are the user's own lists and hold any books in any status; a book can be in several. Later, a collection may also be a saved rule ("finished in 2026") instead of a hand-made list; the model leaves room for that with an optional rule field, added when that feature comes.

**CloudKit rules**, enforced from phase 1:

- Every attribute is optional or has a default value.
- No `@Attribute(.unique)`. Duplicates (the same ISBN twice) are prevented in the operations and resolved after a sync, not by the store.
- Every relationship is optional and has an inverse. No `.deny` delete rules.
- Large data (cover images) uses `@Attribute(.externalStorage)`.
- Once sync is on, schema changes are additive only: new optional attributes and new types. Renames and removals need a new schema version that keeps the old field.

Enums are stored as their `String` raw value, so an unknown value from a newer app version on another device does not break decoding.

## Persistence and sync

- The store is `~/Library/Application Support/Buchhalter/library.store` (plus SQLite's `-wal` and `-shm`). `$BUCHHALTER_HOME` replaces the folder, for a separate test store.
- `BuchhalterCore` builds the `ModelContainer` from the current schema and the migration plan. Tests ask for an in-memory container.
- Every schema is a `VersionedSchema`, starting with `SchemaV1`, listed in one `SchemaMigrationPlan`.
- If the store cannot be opened, the app shows an alert with the path and the error, logs it to stderr and quits. It never deletes, moves or recreates `library.store`.
- At launch the app logs `library: <path>` to stderr.
- Phase 2 turns on `cloudKitDatabase: .private(<container id>)` in the `ModelConfiguration`. Before the first sync, the existing local store is backed up next to itself.
- Export to a plain file (JSON or CSV) comes early, so the user's data never depends on the store alone.

## Data flow

- **Reading:** views use `@Query` for books, readings, collections and list settings. `BuchhalterCore` filters, searches and sorts the fetched arrays in memory (`LibraryLists`, `BookSearch`, `BookSorter`), because `#Predicate` and `SortDescriptor` cannot do German collation with diacritic folding, cannot sort through a to-many relationship (the first author), cannot skip leading articles and cannot express "the latest reading is finished". Hundreds to a few thousand books is fine for this. Lists update by themselves after a change, including changes that arrive through sync.
- **Writing:** views call operations on `Library` (in `BuchhalterCore`) on the main `ModelContext`. The operations hold the rules (a finished reading has a finished date and rating 1–5 or none, collection names are unique, one reading is current) and are what the tests cover. Views never set model properties directly.
- **Undo:** SwiftData's own undo is not used. On macOS 27.2 it reverts an attribute change in memory without marking the context dirty, so the undone value is never saved and the next fetch brings the old one back (inserts and deletes work, attribute changes do not). `Library.change` captures a value snapshot of the library before and after every operation, saves, and registers undo and redo closures with the window's `UndoManager`. A closure applies the difference (creates, changes and deletes objects, writing only the fields that differ), saves, and registers the inverse. One user action is one undo step with an action name. The context's own `undoManager` stays `nil`. Cover bytes are read only for books an operation names, so ordinary actions do not load every cover. Sort and view changes (`ListSettings`) are saved without an undo step. A new field on a model must be added to its record in `LibrarySnapshot.swift` and to `apply`; `UndoTests` and `UndoPersistenceTests` check the current fields, including a fresh fetch and a second `ModelContext`.
- **Background work:** cover normalizing (`CoverImage.normalize`, `@concurrent`) runs off the main actor. Later, imports, book lookups and the assistant's tool calls run in a `@ModelActor` with its own context and save in batches. Model objects never cross actors; `PersistentIdentifier`s and UUIDs do.
- **Threading:** the main context and everything that touches the UI are `@MainActor`.

## UI structure

Each feature's design artifact decides the actual screens. The Library feature's design set the visual language: a deep green accent (#1F6F5C), serif (New York) titles, a fixed palette of 11 generated cover colours.

Two controls are the app's own, in shared views:

- `StatusSegments` looks like a segmented control, but clicking the selected segment clears it. A system segmented `Picker` cannot deselect, and the status is optional.
- Secondary buttons in the book detail use `SecondaryButtonStyle`: a primary-colour label on a neutral fill. On macOS 27 a system bordered button draws its label in the window's tint, which gave dark green text on a dark button in dark mode. Only the prominent action uses the accent.

Sheet forms use a `Grid` whose label column grows to the widest label, because German labels ("Sammlungen", "Abgebrochen am") run longer than the design's 70 pt.

- **Mac:** one main window (one `Window` scene, so one undo stack; closing it quits the app). In list mode a three-column `NavigationSplitView`: a sidebar (Reading, Want to Read, Read, All Books, then the user's Collections; later the Assistant), the books of the selected list, and the book's detail with its readings. In grid mode two columns: the sidebar and the grid, which spans the rest; opening a book pushes its detail onto a `NavigationStack` with a back button. Adding a book is a sheet. The Book menu and ⌘N, ⌘F and ⌘⌫ cover the common actions. A `Settings` scene comes later.
- **iPad:** the same `NavigationSplitView` shows sidebar, list and detail side by side in landscape, as on the Mac. Right-click menus become long-press context menus (the same menus), delete also works by swipe, and the Mac's keyboard shortcuts work with a hardware keyboard. Sheets appear as form sheets. Covers can also come from the Photos picker and the camera.
- **iPhone:** the `NavigationSplitView` collapses to a stack: sidebar, then list, then detail. Views that need a different layout on a small screen get a size-class branch, not a separate copy.

## Localization

- **Languages:** English (development language) and German. The app follows the system language; the user can pick one per app in System Settings → General → Language & Region → Applications.
- **One String Catalog:** `Resources/Localizable.xcstrings`, for every text of the app and of `BuchhalterCore`. Every key has an English and a German value; `LocalizationCatalogTests` fails when a value is missing or not `translated`, when a plural lacks `one` or `other`, and when the spec's German terms differ. Keys are the English text. Where one English text needs two German texts, the key is semantic with a default value (`sortField.finished`: "Finished" / "Beendet", next to the status "Finished" / "Gelesen"). `abandonSheet.title` and `abandonSheet.confirm` are semantic keys too.
- **Why the main bundle:** AppKit's menus and the app's language choice follow the main bundle's localizations (`.lproj` folders, `CFBundleLocalizations`). A package target's resources would sit in a separate `Bundle.module`, which SwiftPM's `swift build` handles unreliably for catalogs and which does not give the app its `de.lproj`. So no target has resources; `make app` runs `xcstringstool compile` into `Contents/Resources/{en,de}.lproj`, and `Text`, `String(localized:)` and `LocalizedStringResource` in both targets resolve against `Bundle.main` with no `bundle:` argument. In the test runner (no catalog) core texts fall back to the English key, which tests may rely on, except for plurals.
- **`make strings`:** builds with `-emit-localized-strings` into `build/strings-build` and syncs the compiler's `.stringsdata` into the catalog, so new keys show up as `new`. (`xcstringstool extract` on the sources alone writes interpolations as `%arg` and was rejected.) The rule: every key is a literal at its call site.
- **Formatting:** dates, page counts, ratings and counts use Foundation's locale-aware `FormatStyle`s through `BookFormatting`, which takes an explicit `Locale`; plurals ("1 book", "3 books" / "1 Buch", "3 Bücher") use the catalog's plural variants. Years print without grouping ("1901", never "1.901"). No texts are built by concatenation; only pieces (dates, numbers) are interpolated.
- **Enums** shown to the user (reading status, sort fields and directions) have a localized display name in `BuchhalterCore`; the stored raw value stays English and fixed.
- **Book data** (titles, authors, notes) is the user's and never translated. Sorting and search use German collation (`de_DE`), case- and diacritic-insensitive, whatever the UI language, so "Ä" sorts with "A" and "boll" finds "Böll".
- **Region:** `-AppleLanguages '(de)'` changes the language, not the region. German date formats ("3. Okt. 2026") need `-AppleLocale de_DE` or a German region.
- **Menus:** the system's standard menu items (Edit, Window, Help) come localized from macOS; the app's own commands come from the catalog.

## Roadmap

Not in the first version. Each comes as its own spec; this section says what the architecture keeps ready for them.

### Book lookup

Pull a book's data from a service: title, authors, publisher, year, pages, language, cover. Search by ISBN or by title and author.

- A `BookLookup` protocol in `BuchhalterCore` with one implementation per service and a fake in tests. Candidates: Open Library (free, no key) and Google Books (free with a key). The spec picks one; the protocol allows a second as fallback.
- Results are proposals: the user sees them and confirms before anything is stored. Every field stays editable, and adding a book never depends on the network.
- Covers are downloaded once into the book's `cover image` (external storage), so the library works offline and syncs with its covers.
- Lookup ids are stored on the book, so its data can be refreshed later.

### Barcode scanning

Add a book by scanning the EAN-13 barcode on its back, which is its ISBN-13.

- iPhone and iPad: the camera with VisionKit's `DataScannerViewController` (barcodes, EAN-13). The scan feeds the ISBN into Book lookup, then into the same confirm-and-add flow.
- Mac: no scanner of its own. Typing or pasting the ISBN goes through the same flow; Continuity Camera (an iPhone as the Mac's camera) is a possible later addition.
- ISBN parsing and checksum validation (ISBN-10 and ISBN-13, conversion between them) live in `BuchhalterCore` from the first version, because manual entry needs them too.

### Assistant

A chat window, like Claude Desktop, for researching book recommendations. The user asks ("three classics like *Buddenbrooks*", "what should I read after *Stoner*"); the assistant answers with suggestions and, when the user agrees, adds them to Want to Read and/or a collection.

- **Providers:** Anthropic and OpenAI, called directly over HTTPS from the app. A `ChatProvider` protocol in `BuchhalterCore` hides the difference: one implementation per provider, a fake in tests. Neither has an official Swift SDK, so the clients are small hand-written `URLSession` clients over each provider's documented HTTP API, with streaming (server-sent events) so text appears as it is written.
- **Anthropic:** the Messages API (`POST https://api.anthropic.com/v1/messages`, headers `x-api-key` and `anthropic-version`). The model is a setting; the default is Claude Opus 5.5 (`claude-opus-5-5`). The plan checks the current model ids, parameters and tool versions against Anthropic's docs at that time.
- **OpenAI:** its current chat API, checked the same way when the feature is planned.
- **Tools:** the assistant works on the library only through tools the app defines and runs itself: search the library, list collections, propose a book, add a book to Want to Read, add a book to a collection, create a collection. The tools call the same core operations as the UI, so the rules hold. Web search (Anthropic's server-side web search tool, OpenAI's equivalent) lets it research beyond its training data. Proposed books go through Book lookup, so they arrive with real data and covers.
- **Confirmation:** the assistant proposes; it never writes on its own. Each add shows as a card in the chat with the book and the target list, and is stored only when the user confirms it. Added books carry origin `assistant` and the reason as origin note.
- **Context:** each request includes a compact summary of the library (finished books with ratings, Want to Read, collection names), so recommendations fit and nothing already read is suggested again.
- **Keys:** API keys are entered in Settings and stored in the Keychain, never in the store, a file or the logs. Without a key, the assistant shows how to add one.
- **History:** conversations are stored as `Conversation` and `ChatMessage`, and sync with the rest of the library. The language follows the app's (English or German), and the assistant answers in it.
- **Costs and errors:** every request is user-triggered; nothing runs in the background. Network, rate-limit and refusal errors show in the chat with a retry.

## Build and test

Following swell and fluff:

| Command | Result |
|---|---|
| `make` / `make build` | `swift build -c release` → `.build/release/buchhalter`, rebuilt only when sources changed |
| `make app` | `build/Buchhalter.app` (binary + `Resources/Info.plist` + compiled catalog), ad-hoc signed with `codesign --sign -`, registered with `lsregister -f` |
| `make install` | Copies the bundle to `/Applications/Buchhalter.app`, unregisters the build copy. Only on the user's request |
| `make test` / `swift test` | `BuchhalterCore` tests, including the catalog test |
| `make strings` | Extracts the texts through the compiler and syncs them into `Resources/Localizable.xcstrings` |

The user starts the app: `open build/Buchhalter.app` runs it on the real library, and manual checks happen there. Agents build and do not start it. For German: `open build/Buchhalter.app --args -AppleLanguages '(de)' -AppleLocale de_DE`.

`open` does not pass shell environment variables. A separate store needs `open --env BUCHHALTER_HOME=<folder> build/Buchhalter.app`, or the binary run directly:

```sh
BUCHHALTER_HOME=<folder> build/Buchhalter.app/Contents/MacOS/Buchhalter 2> <folder>/run.log
```

## Decisions

1. **SwiftData, not SQLite or JSON files.** It gives `@Query`-driven UI, migrations and CloudKit mirroring, which the iPhone and iPad phase needs. The alternative, an own SQLite layer as in fluff, would mean building sync by hand.
2. **SwiftPM and `make` first, Xcode project later.** Agents and the user build and test from the command line, like swell and fluff. An Xcode project is needed only for entitlements, provisioning and the iOS target (iPhone and iPad), so it arrives with phase 2.
3. **CloudKit rules from day one.** Optional attributes, no unique constraints, inverse relationships. Cheaper than migrating the model's shape when sync starts.
4. **Rules live in core operations, views stay thin.** The logic is testable against an in-memory container without a display, and the iPhone and iPad app gets it for free.
5. **English and German from the first feature, in String Catalogs.** Adding a second language later means hunting every hard-coded string; with catalogs from the start each feature carries both languages and the tests catch gaps.
6. **Readings separate from books.** Rereads, abandoned books and "read in year X" fall out of the model instead of needing special fields.
7. **Collections are the user's lists, statuses are queries.** "Read in 2026" and "Classics to Read" are collections the user makes; Reading, Want to Read and Read come from the readings and never need maintaining.
8. **External services behind protocols, never required.** Book lookup and the assistant's providers each sit behind a protocol with a fake, so tests run offline and the app works without network or keys.
9. **The assistant proposes, the user confirms.** The model changes the library only through app-defined tools that call the core operations, and each change needs the user's confirmation.
10. **One String Catalog in the main bundle, compiled by the Makefile.** Per-target catalogs resolve through `Bundle.module`, which is unreliable under `swift build` and leaves AppKit's menus and the language choice without a `de.lproj` in the main bundle.
11. **Built-in lists, filtering, sorting and search run in core over fetched arrays.** `#Predicate` and `SortDescriptor` cannot do German collation, the first author, leading articles or "latest reading is finished". One in-memory rule keeps lists and counts consistent.
12. **Ordered authors through an `Authorship` join model, one `Author` per name.** The first author decides the sort order, and the join keeps real relationships and CloudKit compatibility. Corrected sort names apply to all of an author's books.
13. **`Library` does the undo, from value snapshots.** SwiftData's undo does not persist attribute changes on macOS 27.2 (see Data flow). One mechanism for all operations, one undo step per user action, and the store always holds what the user sees.
14. **Sort and view choices are data, not undo steps.** Each list and collection keeps its sort levels and view mode in `ListSettings`; changing them is never on the undo stack.

## Open points

- The Apple Developer team, CloudKit container id and final bundle id for phase 2.
- Book lookup: Open Library or Google Books, and whether to use both.
- Assistant: whether conversations sync to iPhone and iPad or stay on each device; spending limits per request.
- Import from an existing list (Goodreads CSV, a spreadsheet), if the user has one.
