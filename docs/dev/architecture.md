# Architecture

Buchhalter is a SwiftUI app over a SwiftData store of books and readings. The Mac app comes first. An app for iPhone and iPad follows later: one iOS app target that runs on both. It shares the core library and most views, and the Mac and iOS apps share one library through iCloud (CloudKit).

The UI is in English and German.

This doc describes the code as it is and the direction it takes. The library feature (books, readings, collections, sort, search, undo), book lookup (Complete in Add and Edit Book, Find Cover, three sources) and the Settings window exist; the [Roadmap](#roadmap) lists the features that are planned but not in the first version. The architecture leaves room for them now, so they don't force a rewrite later. Each feature's plan decides the details and updates this doc when it is archived. Sections marked **Direction** describe intent, not code.

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
| `BuchhalterCore` | library | Foundation, SwiftData, ImageIO | The `@Model` types, the versioned schemas and the migration plan, container setup (store location, in-memory for tests), `Library` with the operations that change data (add and edit a book, finish, abandon and repeat a reading, collections, list settings) and its undo, and pure logic (ISBN parsing and checking, author sort names, text folding, sorting, search, list membership, drafts, duplicate check, cover normalizing, formatting), and book lookup (the HTTP client, the Deutsche Nationalbibliothek, Open Library and Google Books services, MARC parsing, matching, merge into a draft, the user's source order, the `SecretStore` protocol, messages). Texts it produces (status names, sort field names, errors, sentences) come from the app's catalog. Fully unit-tested |
| `Buchhalter` | executable `buchhalter` | SwiftUI, Security, AppKit (Mac-only files), BuchhalterCore | The Mac app: `App`, the one window, the Settings window, menus, views, the Keychain store. Every declaration is `@MainActor` by default (`defaultIsolation`) |
| `BuchhalterCoreTests` | Swift Testing | BuchhalterCore | One test file per core area, against in-memory containers |

`Package.swift` excludes `Tests/BuchhalterCoreTests/Fixtures` from the test target (the files are read through `#filePath`, not as resources). It uses tools version 6.2 with the Swift 6 language mode (strict concurrency) and platforms `.macOS("27.0")`, plus `.iOS("27.0")` so nothing Mac-only creeps into the core. There are no package resources and no `defaultLocalization`: the one String Catalog sits outside any target and the Makefile compiles it into the app bundle (see Localization).

When phase 2 or 3 starts, an Xcode project joins the repo. It references the local package for `BuchhalterCore`, holds the macOS app target and the iOS app target (iPhone and iPad) with their entitlements, and the views they share move into a `BuchhalterUI` library in the package. Until then the SwiftPM executable is the app, built like swell and fluff.

## Layout

```
Package.swift
Makefile
Resources/
  Info.plist            CFBundleLocalizations en, de; exported type local.buchhalter.book
  Localizable.xcstrings the one String Catalog, English and German
  AppIcon.icns          the app icon, drawn by Scripts/make-icon.swift (committed)
  PoweredByGoogle.png   Google's attribution graphic, copied into the bundle by `make app`
Scripts/
  make-icon.swift       draws the icon iconset; `make icon` builds AppIcon.icns
  make-isbn-ranges.swift  turns the ISBN range message into Logic/ISBNRanges.swift; `make isbn-ranges`
Sources/
  BuchhalterCore/
    Model/              @Model types in SchemaV1 and SchemaV2 (current), migration plan, enums, derived helpers
    Store/              container, location, Library, operations, undo snapshots
    Logic/              ISBN (checking, hyphenation, generated range table), names, folding, sort, search, lists, draft, duplicates, covers, formatting
    Lookup/             book lookup: HTTP client, DNB, Open Library and Google Books services, MARC parser and mapper, matching, coordinator, merge, source list, key state, secret store protocol, messages
  Buchhalter/
    App/                App, WindowModel, BookSources, KeychainSecretStore
    Views/              shared-ready views (no AppKit): Sidebar, Toolbar, Books, Detail, Sheets (Sheets/Lookup: header, edition picker, lookup model), Settings (Book Lookup pane, key section, help sheet), Common
    Mac/                Mac-only code: AppDelegate, menus, paste, navigation subtitle, store failure alert, window frame and column width restoration, Settings scene content, Find Cover alerts
Tests/
  BuchhalterCoreTests/  one file per core area; Fixtures/ holds recorded DNB, Open Library and Google Books answers, read through #filePath
docs/dev/               this doc
specs/planned/, specs/done/
```

## Data model

`SchemaV2` (Library feature, half-star ratings). The shape below is what the code has; Conversation and ChatMessage are Roadmap.

| Type | Holds | Relationships |
|---|---|---|
| `Book` | `id`, title, subtitle, `isbn13` (normalized digits, for matching and search), `isbnText` (for display; a valid ISBN is stored hyphenated as ISBN-13, "978-3-15-011537-4", other input as typed), publisher, year, page count, language and original language (ISO 639 codes; the original only for a translation, nil when the same), cover image (external storage, JPEG, longest side 1200 px), added date (set to now, editable in the editor as Date Added and in the detail), origin (`manual`, `lookup`, `scan`, `assistant`), origin note. A book added after a lookup has origin `lookup` and the record id ("dnb:991442512", "openlibrary:/books/OL26424294M") in the origin note; a lookup-id attribute can follow as an additive optional attribute when a refresh feature needs it | authorships (one-to-many, cascade), readings (one-to-many, cascade), collections (many-to-many, nullify) |
| `Author` | `id`, name, sort name ("Mann, Thomas"). One per name, reused across books; kept when it has no books left | authorships (cascade) |
| `Authorship` | `id`, position. The ordered join between a book and an author: SwiftData's to-many relationships are unordered, and the first author decides the sort order | book, author |
| `Reading` | One read-through of a book: `id`, status (`wantToRead`, `reading`, `finished`, `abandoned`), started date, ended date (the finish or abandon date), `stars` (rating in half stars, 0.5–5.0, optional), notes, created date. `rating` (whole stars 1–5) is SchemaV1's field: the migration to V2 copies it into `stars`, and nothing reads or writes it since. The current reading of a book is the one created last | book |
| `Collection` | A user-made list of books ("Read in 2026", "Classics to Read", "Owned"): `id`, name, note, sort index, created date | books (inverse of `Book.collections`), settings (cascade) |
| `ListSettings` | The sort levels (as a string such as `author:asc,year:asc`; empty means the default) and the view mode (`list` or `grid`) of one list. `key` names a built-in list (`reading`, `wantToRead`, `read`, `all`); a collection's settings hang off the collection. Sorting is one setting for all lists: the row with `key` `sort` holds it, and the lists' own rows only hold their view mode (their old sort levels are read once, the newest, until the `sort` row exists). No unique constraint, so readers take the newest `updatedAt` | collection |
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
- Every schema is a `VersionedSchema`, listed in one `SchemaMigrationPlan`: `SchemaV1`, then `SchemaV2`. The V1 → V2 stage is custom: SwiftData adds `Reading.stars` (additive, so CloudKit-safe) and `didMigrate` copies each whole-star `rating` into it. `MigrationTests` runs it on a V1 store in a temporary folder.
- If the store cannot be opened, the app shows an alert with the path and the error, logs it to stderr and quits. It never deletes, moves or recreates `library.store`.
- At launch the app logs `library: <path>` to stderr.
- Phase 2 turns on `cloudKitDatabase: .private(<container id>)` in the `ModelConfiguration`. Before the first sync, the existing local store is backed up next to itself.
- Until phase 2 the library exists only on this Mac. iCloud sync is its only protection: there is no file export and no separate backup (see Decisions, 20).

## Data flow

- **Reading:** views use `@Query` for books, readings, collections and list settings. `BuchhalterCore` filters, searches and sorts the fetched arrays in memory (`LibraryLists`, `BookSearch`, `BookSorter`), because `#Predicate` and `SortDescriptor` cannot do German collation with diacritic folding, cannot sort through a to-many relationship (the first author), cannot skip leading articles and cannot express "the latest reading is finished". Hundreds to a few thousand books is fine for this. Lists update by themselves after a change, including changes that arrive through sync.
- **Writing:** views call operations on `Library` (in `BuchhalterCore`) on the main `ModelContext`. The operations hold the rules (a finished reading has a finished date and a rating of 0.5–5 stars in half steps or none, collection names are unique, one reading is current) and are what the tests cover. Views never set model properties directly.
- **Undo:** SwiftData's own undo is not used. On macOS 27.2 it reverts an attribute change in memory without marking the context dirty, so the undone value is never saved and the next fetch brings the old one back (inserts and deletes work, attribute changes do not). `Library.change` captures a value snapshot of the library before and after every operation, saves, and registers undo and redo closures with the window's `UndoManager`. A closure applies the difference (creates, changes and deletes objects, writing only the fields that differ), saves, and registers the inverse. One user action is one undo step with an action name. The context's own `undoManager` stays `nil`. Cover bytes are read only for books an operation names, so ordinary actions do not load every cover. Sort and view changes (`ListSettings`) are saved without an undo step. A new field on a model must be added to its record in `LibrarySnapshot.swift` and to `apply`; `UndoTests` and `UndoPersistenceTests` check the current fields, including a fresh fetch and a second `ModelContext`.
- **Book lookup:** Complete in the editor sheet runs `BookLookup.run` (`@concurrent`) in a task owned by the sheet's `LookupModel`. `BookLookup` holds the active services in the user's order (`BookSources` builds it from Settings). Each source asked reports `LookupEvent`s (`asking`, `answered`, `failed`) on the main actor: to the call's `onEvent`, which drives the status line, and to the `observer`, which `BookSources` uses to keep the Google Books key state (`works`, `rejected`) current for every caller. A failing source is skipped; only when every source asked has failed does the call throw `noSourceReached`. HTTP, XML and JSON parsing, mapping and matching run off the main actor; only value types (`LookupRecord`, `EditionList`, `LookupOutcome`) come back. The model checks a `generation` after every await, so Stop, Save, Cancel or a newer Complete drop a late answer. Author resolution (`Library.lookupAuthors`) and the merge (`LookupResult.merge`) run on the main actor against the draft as it is when the answer arrives, so values typed meanwhile win. Nothing is saved during a lookup; the draft is saved with the book as one undo step.
- **Background work:** cover normalizing (`CoverImage.normalize`, `@concurrent`) runs off the main actor. Later, imports, book lookups and the assistant's tool calls run in a `@ModelActor` with its own context and save in batches. Model objects never cross actors; `PersistentIdentifier`s and UUIDs do.
- **Threading:** the main context and everything that touches the UI are `@MainActor`.

## UI structure

Each feature's design artifact decides the actual screens. The Library feature's design set the visual language: a deep green accent (#1F6F5C), serif (New York) titles, a fixed palette of 11 generated cover colours.

The app's own controls, in shared views:

- `StatusSegments` looks like a segmented control, but clicking the selected segment clears it. A system segmented `Picker` cannot deselect, and the status is optional.
- Secondary buttons in the book detail use `SecondaryButtonStyle`: a primary-colour label on a neutral fill. On macOS 27 a system bordered button draws its label in the window's tint, which gave dark green text on a dark button in dark mode. Only the prominent action uses the accent.
- Pop-up buttons and link buttons draw their labels in the tint too, and the deep green is unreadable on a dark popover. The sort popover therefore uses the system colours (`.tint(nil)`).
- `DateField` picks every date: a button with the day that opens a graphical calendar in a popover, which closes when a day is picked. The system date field's calendar stays open after a pick and SwiftUI cannot close it.
- `StarRatingControl` sets ratings in half stars: a first click on a star gives it whole, a second click on the same star makes it half (`StarClick`). The arrow keys and VoiceOver step in halves.

The editor sheet (650 pt wide) has a header with the Complete button (`LookupHeader`): a grey explanation, a status line while running, an amber no-match hint, a red unreachable hint with Try Again, or a green banner with Undo. After a lookup, filled fields get a light green fill and border (`lookupFilled`), differing fields get a note "DNB: 2009 · Use" (`LookupOfferNote`), and the cover gets an outline or a "Use DNB cover" offer. All of this is derived from `LookupResult` and the current draft, not stored per field. Several matches open `EditionPickerSheet` over the editor: a `List(selection:)` whose double-click is `contextMenu(forSelectionType:primaryAction:)`, with covers loaded through the lookup service.

The Settings pane lists the three sources in a bordered `List` of fixed height (rows drag with `onMove`; a checkbox, the name, a description or the Google Books badge, a handle). Google Books is greyed and disabled without a saved key. Below it the Google Books group holds the key section: a `SecureField` with Save Key, a "Checking…" state, a red or amber message, the masked key (17 dots and the last four characters) with Change… and Remove, and a line that says what is known about the key (`GoogleBooksKeyLine`). When no source is on, Complete and Find Cover are disabled with a tooltip. Find Cover's two alerts have their own state (`WindowModel.coverAlert`) and a Mac-only modifier, because "Open Settings…" needs `openSettings`. The edition picker shows Google's "powered by Google" graphic (`PoweredByGoogleMark`, loaded through ImageIO from the bundle) and a `Google Books` link to the book's page on every Google row.

The book detail edits in place (`InlineFields.swift`). Clicking the title, subtitle, authors, year, pages, publisher or ISBN turns it into a plain text field: Return or clicking elsewhere saves, Escape cancels. A value the library refuses (empty title, invalid ISBN, year outside 1–9999) keeps the field open with a red outline on Return, and is dropped when focus leaves. The two languages are menus with the editor's choices, Date Added opens a calendar. Authors are typed as names separated by commas; a known author keeps their sort name. Empty fields show their placeholders only while the pointer is over the header. Each change is one "Edit Book" undo step through `Library.updateDetails`, which changes only the book's own fields, never the readings or collections.

In the editor, Finished on is optional like Started: a finished reading without a date (most of the LibraryThing bulk import) stays undated when the book is saved.

The editor does not scroll: it sizes to its content, so the banner, hints and notes make the sheet taller instead of hiding fields. Leaving the ISBN field rewrites a valid ISBN in its hyphenated ISBN-13 form; saving does the same, and display formats older books' `isbnText` too.

Sheet forms use a `Grid` whose label column grows to the widest label, because German labels ("Sammlungen", "Abgebrochen am") run longer than the design's 70 pt.

- **Mac:** one main window (one `Window` scene, so one undo stack; closing it quits the app). In list mode a three-column `NavigationSplitView`: a sidebar (Reading, Want to Read, Read, All Books in the user's order, then the user's Collections; later the Assistant), the books of the selected list, and the book's detail with its readings. In grid mode two columns: the sidebar and the grid, which spans the rest; opening a book pushes its detail onto a `NavigationStack` with a back button. Adding a book is a sheet. The Book menu and ⌘N, ⌘F and ⌘⌫ cover the common actions. A `Settings` scene (⌘,, `Mac/SettingsView`) holds one tab, Book Lookup, 620 pt wide; its pane and the key help sheet are shared-ready views under `Views/Settings`.
- **Mac view state:** per Mac, in UserDefaults: the order and switches of the book sources (`lookupSources`, `LookupSourceList`, "dnb:on,openLibrary:on,googleBooks:off"), the state of the Google Books key (`googleBooksKeyState`: `works`, `unchecked`, `rejected`; no secret), the selected list (`selectedList`), the selected book and the book open in grid mode (`selectedBook`, `openBook`, restored at launch when the book is still in the list), the sidebar and list column widths (`sidebarWidth`, `listWidth`: SwiftUI saves the split view's frames but lays the columns out at their ideal widths at launch, so `restoresWindowFrame(named:)` saves the widths on each split view resize and sets the dividers on every new split view and again after restoring the frame) and the order of the built-in lists (`libraryListOrder`, dragged in the sidebar, `LibraryListOrder`).
- **Window frame:** SwiftUI restores it only through state restoration, which macOS skips when "Close windows when quitting an application" is on, and centres the window on the main display when it first shows it; `defaultWindowPlacement` can only place on the main display. So `restoresWindowFrame(named:)` (Mac-only) saves AppKit's frame descriptor (which names the display) under `WindowFrame main` on every move and resize, and applies it when the window first becomes key, after SwiftUI's placement. The first time it reads SwiftUI's own `NSWindow Frame main`.
- **iPad:** the same `NavigationSplitView` shows sidebar, list and detail side by side in landscape, as on the Mac. Right-click menus become long-press context menus (the same menus), delete also works by swipe, and the Mac's keyboard shortcuts work with a hardware keyboard. Sheets appear as form sheets. Covers can also come from the Photos picker and the camera.
- **iPhone:** the `NavigationSplitView` collapses to a stack: sidebar, then list, then detail. Views that need a different layout on a small screen get a size-class branch, not a separate copy.

## Localization

- **Languages:** English (development language) and German. The app follows the system language; the user can pick one per app in System Settings → General → Language & Region → Applications.
- **One String Catalog:** `Resources/Localizable.xcstrings`, for every text of the app and of `BuchhalterCore`. Every key has an English and a German value; `LocalizationCatalogTests` fails when a value is missing or not `translated`, when a plural lacks `one` or `other`, and when the spec's German terms differ. Keys are the English text. Where one English text needs two German texts, the key is semantic with a default value (`sortField.finished`: "Finished" / "Beendet", next to the status "Finished" / "Gelesen"). `abandonSheet.title` and `abandonSheet.confirm` are semantic keys too.
- **Why the main bundle:** AppKit's menus and the app's language choice follow the main bundle's localizations (`.lproj` folders, `CFBundleLocalizations`). A package target's resources would sit in a separate `Bundle.module`, which SwiftPM's `swift build` handles unreliably for catalogs and which does not give the app its `de.lproj`. So no target has resources; `make app` runs `xcstringstool compile` into `Contents/Resources/{en,de}.lproj`, and `Text`, `String(localized:)` and `LocalizedStringResource` in both targets resolve against `Bundle.main` with no `bundle:` argument. In the test runner (no catalog) core texts fall back to the English key, which tests may rely on, except for plurals.
- **`make strings`:** builds with `-emit-localized-strings` into `build/strings-build` and syncs the compiler's `.stringsdata` into the catalog, so new keys show up as `new`. (`xcstringstool extract` on the sources alone writes interpolations as `%arg` and was rejected.) The rule: every key is a literal at its call site.
- **Formatting:** dates, page counts, ratings ("3.5" / "3,5" stars) and counts use Foundation's locale-aware `FormatStyle`s through `BookFormatting`, which takes an explicit `Locale`; plurals ("1 book", "3 books" / "1 Buch", "3 Bücher") use the catalog's plural variants. Years print without grouping ("1901", never "1.901"). No texts are built by concatenation; only pieces (dates, numbers) are interpolated.
- **Enums** shown to the user (reading status, sort fields and directions) have a localized display name in `BuchhalterCore`; the stored raw value stays English and fixed.
- **Book data** (titles, authors, notes) is the user's and never translated. Sorting and search use German collation (`de_DE`), case- and diacritic-insensitive, whatever the UI language, so "Ä" sorts with "A" and "boll" finds "Böll".
- **Region:** `-AppleLanguages '(de)'` changes the language, not the region. German date formats ("3. Okt. 2026") need `-AppleLocale de_DE` or a German region.
- **Menus:** the system's standard menu items (Edit, Window, Help) come localized from macOS; the app's own commands come from the catalog.

## Roadmap

Not in the first version. Each comes as its own spec; this section says what the architecture keeps ready for them.

### Book lookup

Built: Complete in Add and Edit Book pulls a book's data and cover. It searches by a valid ISBN, or by title and author.

- **Sources:** the Deutsche Nationalbibliothek (SRU, MARC 21 over XML, anonymous, CC0 metadata), Open Library (anonymous) and Google Books (API v1, the user's own key). The user switches each on or off and drags them into an order in Settings (`LookupSourceList`); Complete and Find Cover ask the sources that are on, from top to bottom, and the first that finds the book supplies the result. A source that cannot be reached (offline, timeout, server error, or a key Google refuses) is skipped and the next is asked; only when every source asked has failed does Complete show the red hint ("Can't reach any book source", or the source's name when only one was asked) and Find Cover its alert. A new user starts with DNB, Open Library, then Google Books last, off until a key is saved. Google Books counts only with a saved key. Covers come from the DNB's MVB cover service (undocumented; any failure means no cover), Open Library's covers API or Google's content URLs.
- **Layers:** `HTTPClient` (ephemeral `URLSession`, User-Agent "Buchhalter/0.1 (personal book app)") and `BookLookupService` (`DNBService`, `OpenLibraryService`, `GoogleBooksService`) are protocols with fakes, so the parsers and URL building are tested against recorded answers. `MARCXMLParser` reads structure, `DNBRecordMapper` applies the bibliographic rules (carrier filter, title markers, year, pages, language, ISBN, author headings), `LookupMatching` filters real matches and orders editions, `BookLookup` is the coordinator (an ordered list of services and an observer), `LookupMerge` merges a record into a `BookDraft`, `LookupMessages` holds every sentence.
- **Find Cover:** when a book has no cover, the detail's cover shows a Find Cover button and "or drop an image here" over the generated cover while the pointer is over it or an image is dragged onto it; the cover's context menu offers Find Cover too (`BookLookup.findCover`). It searches by the ISBN, then by title and authors (`LookupQuery.coverQueries`, with the title cut at the first colon or parenthesis, since LibraryThing titles carry "A Novel" or "(Penguin Classics)"). Each search asks every source that is on and takes the first cover that downloads: the matching editions' own covers first, then Open Library's work cover, which can show another edition of the same book. Complete never uses the work cover. At most 5 editions per source and search. Unlike Complete it falls through to the next source when one has no cover, because only the image is used. The DNB holds no UK or US editions, so English books depend on Open Library; in a sample of 30 English books from the library, 17 had an edition cover and 26 a cover by any of these steps. No cover gives the alert "No cover found" (with a second sentence and an Open Settings… button when Google Books has no key or is off); a cover set by hand while it runs wins.
- **Merge rule:** an empty field is filled, an equal one stays, a different one keeps the user's value and is offered. A typed title is only offered. Status, dates, rating, notes and collections are never touched.

- Results are proposals: the user sees them and confirms before anything is stored. Every field stays editable, and adding a book never depends on the network.
- Covers are downloaded once into the book's `cover image` (external storage), so the library works offline and syncs with its covers.
- The lookup id is stored in the book's origin note until a schema change adds an attribute, so its data can be refreshed later. Phase 2's sandbox needs the entitlement `com.apple.security.network.client`; today the app is unsandboxed.
- The assistant and barcode scanning reuse `BookLookup` through the `\.bookLookup` environment entry and the same confirm-and-add flow.

### Google Books

The third source. The user creates a free key in the Google Cloud Console (the app's help sheet lists the steps) and pastes it in Settings.

- **Key:** stored in the login Keychain as a generic password, service `Buchhalter Google Books`, account `api-key`, with `kSecAttrComment` holding the last four characters, so the masked key shows without reading the secret. The names carry no bundle id, so the item survives the change from `local.buchhalter`. `KeychainSecretStore` (an actor in the app target, behind the `SecretStore` protocol in the core) caches the secret after the first read. Without a Developer team the app is ad-hoc signed, so macOS asks once per build when the app reads the secret ("Always Allow"); asking for attributes only does not prompt. The key is read only when Google Books is actually asked. It never goes into the store, a file, a URL or a log.
- **Request:** `GET https://www.googleapis.com/books/v1/volumes` with `q=isbn:<isbn13>` or `intitle:<word>` and `inauthor:<word>` terms joined by `+`, `printType=books`, `maxResults=40`, `projection=full` and a `fields` list. The key goes in the `X-goog-api-key` header (checked against the live API), so it cannot show up in an error, a fixture or a log.
- **Failures:** 401, 403 and 429 mean a rejected key (revoked, API not enabled, quota used up); 400 only when the answer names the key (`API_KEY_INVALID`, `keyInvalid`, "API key not valid"); anything else is unreachable. A rejected key turns the Settings line red but leaves Google Books on.
- **Checking a key:** Save Key runs one search (`isbn:9781804993750`, `maxResults=1`) with the key under test, before anything is saved. Works: saved, Google Books switched on where it stands. Rejected: nothing saved. Unreachable: Save Anyway saves it unchecked.
- **Records:** printed books only (`printType` is `BOOK`, `saleInfo.isEbook` is not true; Google has no audiobook flag). Authors come as "Nick Newman" (a role in brackets is cut), the language as a two-letter code ("pt-BR" gives "pt"), a page count of 0 means none. The record id "googlebooks:<volume id>" is the book's origin note.
- **Covers:** a record has a cover reference when the list answer has `imageLinks.thumbnail`. Small: the content URL with `zoom=1`. Large: a single-volume request (`fields=volumeInfo/imageLinks`), then the largest link on offer, as https and without `edge=curl`. Google serves a grey "image not available" picture for a volume without a cover; `GoogleBooksCover.isPlaceholder` recognizes it by pixel size and byte count (recorded in `googlebooks-placeholder.png`) and it counts as no cover. For some volumes the only links are small (128 px wide); `zoom=2` gave 300 px for the one volume tried, but `zoom=3` returned a grey picture of another size, which the placeholder check would not recognize, so no size is guessed.
- **Branding:** Google's rules ask for the "powered by Google" graphic next to results and a prominent link to the book's page on each. The edition picker shows both for Google results. The rules also forbid reordering or filtering results; the app filters to printed matches and shows newest first, like for the other sources. This is a deliberate reading for a lookup aid.
- **Lists are never truncated:** Google's `totalItems` is an estimate and answers stop at 40, so "100 newest records" would be wrong (`LookupSource.maximumListedRecords`).
- Phase 2's sandbox needs `com.apple.security.network.client` (already noted above). A proper signature also allows the data protection keychain (`kSecUseDataProtectionKeychain` with a `keychain-access-groups` entitlement), which avoids the per-build prompt.

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
| `make app` | `build/Buchhalter.app` (binary + `Resources/Info.plist` + `AppIcon.icns` + `PoweredByGoogle.png` + compiled catalog), ad-hoc signed with `codesign --sign -`, registered with `lsregister -f` |
| `make install` | Copies the bundle to `/Applications/Buchhalter.app`, unregisters the build copy. Only on the user's request |
| `make test` / `swift test` | `BuchhalterCore` tests, including the catalog test |
| `make strings` | Extracts the texts through the compiler and syncs them into `Resources/Localizable.xcstrings` |
| `make isbn-ranges` | Downloads the International ISBN Agency's range message to `build/RangeMessage.xml` and regenerates `Sources/BuchhalterCore/Logic/ISBNRanges.swift` (committed). Run it when new ISBN ranges matter |
| `make icon` | Redraws the app icon with `Scripts/make-icon.swift` and builds `Resources/AppIcon.icns` with `iconutil`. The artwork is full-bleed and opaque, because macOS 26 and later mask such an icon to their rounded square and shrink an icon with its own margin onto a grey plate |

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
14. **Sort and view choices are data, not undo steps.** One sort applies to every list and collection (the user's choice); each list and collection keeps its own view mode. Both live in `ListSettings`, and changing them is never on the undo stack.
15. **User-ordered sources, a failing source is skipped.** The user decides which sources are on and in what order (Settings); Complete and Find Cover ask them top to bottom and move on when one cannot be reached or finds nothing. It replaces the first version's rule (DNB first, no fallback on a DNB failure), which kept a mostly English source from quietly filling a German library: now the user chooses the order, and an outage of one source no longer blocks the others. Only when every source asked has failed does the red hint appear, and it says so.
16. **Lookup ids in `originNote`, not a new attribute.** Both origin fields exist in SchemaV1 and in the undo snapshot, and nothing reads a lookup id yet, so a schema version and migration on the real library would buy nothing now.
17. **The merge is derived, not flagged.** `LookupResult` keeps the draft before Complete and the record's values; highlights, notes and Undo are functions of that and the current draft, so they cannot drift from what the user edits.
18. **ISBN hyphens from the official range table, generated into code.** Hyphen positions depend on the registration group and the publisher, so no fixed pattern is right. `make isbn-ranges` downloads the International ISBN Agency's `export_rangemessage.xml` and `Scripts/make-isbn-ranges.swift` writes `Logic/ISBNRanges.swift` (one text table, parsed once), which is committed: no package resources, no network at build time. An ISBN outside known ranges prints as the prefix and ten digits.
19. **Half stars as a new attribute, not a changed one.** `Reading.stars: Double?` sits next to SchemaV1's `rating: Int?` instead of changing its type: a type change is not allowed once CloudKit sync is on, and a lightweight-compatible additive change plus one copy in `didMigrate` keeps the old value.
20. **Sync, no export and no backup.** The user decided on 2026-11-15 to rely on iCloud sync (phase 2), the way Health or Notes keep their data in iCloud. Sync protects against losing a device, not against a mistake: a deletion reaches iCloud within seconds. That trade-off is accepted; no file export, no in-app backup.
21. **The Google Books key is in the Keychain and travels in a header.** AGENTS.md keeps keys out of the store, files and logs; the header (`X-goog-api-key`) also keeps it out of URLs, errors and fixtures. The Keychain code is in the app target behind a core protocol, because the core imports only Foundation and SwiftData and the Keychain cannot be unit-tested without touching the real one.
22. **`BookSources` is the one app-wide holder of lookup settings.** An `@Observable` object created by `BuchhalterApp` and injected into the window and Settings. It builds `BookLookup` from the user's list, so a switch in Settings enables Complete and Find Cover in an open sheet at once, and it follows the key's health through the `BookLookup` observer. `\.bookLookup` stays the injection point for previews, barcode scanning and the assistant.

## Open points

- The Apple Developer team, CloudKit container id and final bundle id for phase 2. With them: the data protection keychain for the Google Books key (no per-build prompt) and the sandbox entitlements (`com.apple.security.network.client`).
- Book lookup: a lookup-id attribute (SchemaV3) once a refresh feature exists.
- The order of the built-in lists is per Mac (UserDefaults); with sync it may move into the store or `NSUbiquitousKeyValueStore`.
- Assistant: whether conversations sync to iPhone and iPad or stay on each device; spending limits per request.
- Import from an existing list (Goodreads CSV, a spreadsheet), if the user has one.
