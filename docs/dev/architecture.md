# Architecture

Buchhalter is a SwiftUI app over a SwiftData store of books and readings. The Mac app comes first. An iOS app follows later; it shares the core library and most views, and the two apps share one library through iCloud (CloudKit).

The UI is in English and German.

This doc sets the direction before any code exists. The [Roadmap](#roadmap) lists the features that are planned but not in the first version; the architecture leaves room for them now, so they don't force a rewrite later. Each feature's plan decides the details and updates this doc when it is archived. Sections marked **Direction** describe intent, not code.

## Phases

| Phase | What | Needs |
|---|---|---|
| 1. Mac, local | macOS app, local SwiftData store, no sync. SwiftPM + `make`, ad-hoc signed, bundle id `local.buchhalter` | Nothing beyond Xcode |
| 2. iCloud sync | The same store, mirrored to a private CloudKit database | A paid Apple Developer team, a CloudKit container, a reverse-DNS bundle id under that team, an Xcode project for entitlements and provisioning |
| 3. iOS | iOS 27 app target in the same Xcode project, using `BuchhalterCore` and the shared views | Phase 2 |

The features in the [Roadmap](#roadmap) are independent of the phases: book lookup and the assistant can come in phase 1 on the Mac; barcode scanning is best on iOS.

No signing identity is installed on this Mac yet (`security find-identity -p codesigning` finds none), so phase 1 stays unsigned apart from the ad-hoc signature. The data model follows CloudKit's rules from phase 1, so turning on sync in phase 2 needs no migration of the model's shape.

## Targets

**Direction.**

| Target | Kind | Imports | Contents |
|---|---|---|---|
| `BuchhalterCore` | library | Foundation, SwiftData | Its own String Catalog for the texts it produces (status names, statistics, errors). The `@Model` types, the versioned schemas and the migration plan, container setup (store location, in-memory for tests), the operations that change data (add a book, start and finish a reading, rate, shelve, delete), queries and sort descriptors used by more than one view, and pure logic (ISBN parsing and checking, statistics, search folding, import and export). Fully unit-tested |
| `Buchhalter` | executable `buchhalter` | SwiftUI, AppKit (Mac-only files), BuchhalterCore | The Mac app: `App`, scenes, menus, `Settings`, views |
| `BuchhalterCoreTests` | Swift Testing | BuchhalterCore | One test file per core area, against in-memory containers |

`Package.swift` uses a Swift 6 tools version with the Swift 6 language mode (strict concurrency) and platforms `.macOS("27.0")`, plus `.iOS("27.0")` for the core from the start, so nothing Mac-only creeps into it. `defaultLocalization` is `"en"`, and each target with texts declares its `Resources/` folder with the String Catalog.

When phase 2 or 3 starts, an Xcode project joins the repo. It references the local package for `BuchhalterCore`, holds the macOS and iOS app targets with their entitlements, and the views both apps share move into a `BuchhalterUI` library in the package. Until then the SwiftPM executable is the app, built like swell and fluff.

## Layout

**Direction.**

```
Package.swift
Makefile
Resources/              Info.plist (CFBundleLocalizations en, de), app icon
Sources/
  BuchhalterCore/
    Model/              @Model types, SchemaV1…, migration plan
    Store/              container setup, store location, operations
    Logic/              ISBN, statistics, search, import/export
    Resources/          Localizable.xcstrings
  Buchhalter/
    App/                App, scenes, commands (menus)
    Views/              shared-ready views (no AppKit)
    Mac/                Mac-only code
    Resources/          Localizable.xcstrings
Tests/
  BuchhalterCoreTests/
docs/dev/               this doc
specs/planned/, specs/done/
```

## Data model

**Direction.** The starting shape. The first spec that stores books fixes it in `SchemaV1`.

| Type | Holds | Relationships |
|---|---|---|
| `Book` | Title, subtitle, ISBN-13 (optional), publisher, year, page count, language, cover image (external storage), added date, origin (`manual`, `lookup`, `scan`, `assistant`), origin note (for example the assistant's reason for a recommendation), lookup ids (for example an Open Library work id) | authors (many-to-many), readings (one-to-many, cascade), collections (many-to-many) |
| `Author` | Name, sort name ("Mann, Thomas") | books |
| `Reading` | One read-through of a book: status (`wantToRead`, `reading`, `finished`, `abandoned`), started and finished dates, rating (1–5, optional), notes | book |
| `Collection` | A user-made list of books ("Read in 2026", "Classics to Read", "Owned"), name, note, order | books |
| `Conversation` | Roadmap: one assistant chat: title, created date, provider and model used | messages (one-to-many, cascade) |
| `ChatMessage` | Roadmap: one turn: role, text, the books it added or proposed, date | conversation |

A book read twice has two readings. The sidebar's Reading, Want to Read and Read are queries over readings, not stored lists. Collections are the user's own lists and hold any books in any status; a book can be in several. Later, a collection may also be a saved rule ("finished in 2026") instead of a hand-made list; the model leaves room for that with an optional rule field, added when that feature comes.

**CloudKit rules**, enforced from phase 1:

- Every attribute is optional or has a default value.
- No `@Attribute(.unique)`. Duplicates (the same ISBN twice) are prevented in the operations and resolved after a sync, not by the store.
- Every relationship is optional and has an inverse. No `.deny` delete rules.
- Large data (cover images) uses `@Attribute(.externalStorage)`.
- Once sync is on, schema changes are additive only: new optional attributes and new types. Renames and removals need a new schema version that keeps the old field.

Enums are stored as their `String` raw value, so an unknown value from a newer app version on another device does not break decoding.

## Persistence and sync

- The store is `~/Library/Application Support/Buchhalter/library.store` (plus SQLite's `-wal` and `-shm`). `$BUCHHALTER_HOME` replaces the folder, for agents and manual tests.
- `BuchhalterCore` builds the `ModelContainer` from the current schema and the migration plan. Tests ask for an in-memory container.
- Every schema is a `VersionedSchema`, starting with `SchemaV1`, listed in one `SchemaMigrationPlan`.
- Phase 2 turns on `cloudKitDatabase: .private(<container id>)` in the `ModelConfiguration`. Before the first sync, the existing local store is backed up next to itself.
- Export to a plain file (JSON or CSV) comes early, so the user's data never depends on the store alone.

## Data flow

**Direction.**

- **Reading:** views use `@Query` with the predicates and sort descriptors from `BuchhalterCore`, so every list updates by itself after a change, including changes that arrive through sync.
- **Writing:** views call operations in `BuchhalterCore` (for example "finish reading on date with rating") on the main `ModelContext`. The operations hold the rules (a finished reading has a finished date, one open reading per book) and are what the tests cover. Views never set model properties that carry such rules directly.
- **Background work:** imports, book lookups and the assistant's tool calls run in a `@ModelActor` with its own context and save in batches. Model objects never cross actors; `PersistentIdentifier`s do.
- **Threading:** the main context and everything that touches the UI are `@MainActor`.

## UI structure

**Direction.** Each feature's design artifact decides the actual screens.

- **Mac:** one main window with a `NavigationSplitView`: a sidebar (Reading, Want to Read, Read, All Books, then the user's Collections; later the Assistant), a list or grid of books in the middle, and the book's detail with its readings on the right. Adding a book is a sheet. Menus and keyboard shortcuts for the common actions, a `Settings` scene.
- **iOS:** the same `NavigationSplitView` collapses to a stack on iPhone. Views that need a different layout on a small screen get a size-class branch, not a separate copy.

## Localization

**Direction.**

- **Languages:** English (development language) and German. The app follows the system language; the user can pick one per app in System Settings → General → Language & Region → Applications.
- **String Catalogs:** one `Localizable.xcstrings` per target with texts. Every key has an English and a German value; a test fails when a German value is missing or marked as needing review.
- **Bundle lookup:** a SwiftPM target's catalog compiles into its resource bundle, not the main bundle. Views and core code look up texts in their own target's bundle (`Bundle.module`), and `make app` copies the resource bundles into `Buchhalter.app/Contents/Resources/`. The first plan settles the exact mechanism and checks it in both languages.
- **Formatting:** dates, page counts, ratings and durations use Foundation's locale-aware `FormatStyle`s; plurals ("1 book", "3 books" / "1 Buch", "3 Bücher") use the catalog's plural variants. No texts are built by concatenation.
- **Enums** shown to the user (reading status) have a localized display name in `BuchhalterCore`; the stored raw value stays English and fixed.
- **Book data** (titles, authors, notes) is the user's and never translated. Sorting and search use the current locale's collation and fold case and diacritics, so "Ä" sorts with "A" and "boll" finds "Böll".
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

- iOS: the camera with VisionKit's `DataScannerViewController` (barcodes, EAN-13). The scan feeds the ISBN into Book lookup, then into the same confirm-and-add flow.
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

**Direction**, following swell and fluff:

| Command | Result |
|---|---|
| `make` / `make build` | `swift build -c release` → `.build/release/buchhalter`, rebuilt only when sources changed |
| `make app` | `build/Buchhalter.app` (binary + `Resources/Info.plist` + icon), ad-hoc signed with `codesign --sign -`, registered with `lsregister -f` |
| `make install` | Copies the bundle to `/Applications/Buchhalter.app`, unregisters the build copy |
| `make test` / `swift test` | `BuchhalterCore` tests |

Open the app with `open build/Buchhalter.app`. A directly executed binary gets no proper app activation. From an agent, run it in the background with a scratch store:

```sh
BUCHHALTER_HOME=<scratchpad>/library build/Buchhalter.app/Contents/MacOS/Buchhalter 2> <scratchpad>/run.log
```

## Decisions

1. **SwiftData, not SQLite or JSON files.** It gives `@Query`-driven UI, migrations and CloudKit mirroring, which the iOS phase needs. The alternative, an own SQLite layer as in fluff, would mean building sync by hand.
2. **SwiftPM and `make` first, Xcode project later.** Agents and the user build and test from the command line, like swell and fluff. An Xcode project is needed only for entitlements, provisioning and the iOS target, so it arrives with phase 2.
3. **CloudKit rules from day one.** Optional attributes, no unique constraints, inverse relationships. Cheaper than migrating the model's shape when sync starts.
4. **Rules live in core operations, views stay thin.** The logic is testable against an in-memory container without a display, and the iOS app gets it for free.
5. **English and German from the first feature, in String Catalogs.** Adding a second language later means hunting every hard-coded string; with catalogs from the start each feature carries both languages and the tests catch gaps.
6. **Readings separate from books.** Rereads, abandoned books and "read in year X" fall out of the model instead of needing special fields.
7. **Collections are the user's lists, statuses are queries.** "Read in 2026" and "Classics to Read" are collections the user makes; Reading, Want to Read and Read come from the readings and never need maintaining.
8. **External services behind protocols, never required.** Book lookup and the assistant's providers each sit behind a protocol with a fake, so tests run offline and the app works without network or keys.
9. **The assistant proposes, the user confirms.** The model changes the library only through app-defined tools that call the core operations, and each change needs the user's confirmation.

## Open points

- The Apple Developer team, CloudKit container id and final bundle id for phase 2.
- Book lookup: Open Library or Google Books, and whether to use both.
- Assistant: whether conversations sync to iOS or stay on each device; spending limits per request.
- Import from an existing list (Goodreads CSV, a spreadsheet), if the user has one.
