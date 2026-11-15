# Architecture

Buchhalter is a SwiftUI app over a SwiftData store of books and readings. The Mac app comes first. An iOS app follows later; it shares the core library and most views, and the two apps share one library through iCloud (CloudKit).

This doc sets the direction before any code exists. Each feature's plan decides the details and updates this doc when it is archived. Sections marked **Direction** describe intent, not code.

## Phases

| Phase | What | Needs |
|---|---|---|
| 1. Mac, local | macOS app, local SwiftData store, no sync. SwiftPM + `make`, ad-hoc signed, bundle id `local.buchhalter` | Nothing beyond Xcode |
| 2. iCloud sync | The same store, mirrored to a private CloudKit database | A paid Apple Developer team, a CloudKit container, a reverse-DNS bundle id under that team, an Xcode project for entitlements and provisioning |
| 3. iOS | iOS 27 app target in the same Xcode project, using `BuchhalterCore` and the shared views | Phase 2 |

No signing identity is installed on this Mac yet (`security find-identity -p codesigning` finds none), so phase 1 stays unsigned apart from the ad-hoc signature. The data model follows CloudKit's rules from phase 1, so turning on sync in phase 2 needs no migration of the model's shape.

## Targets

**Direction.**

| Target | Kind | Imports | Contents |
|---|---|---|---|
| `BuchhalterCore` | library | Foundation, SwiftData | The `@Model` types, the versioned schemas and the migration plan, container setup (store location, in-memory for tests), the operations that change data (add a book, start and finish a reading, rate, shelve, delete), queries and sort descriptors used by more than one view, and pure logic (ISBN parsing and checking, statistics, search folding, import and export). Fully unit-tested |
| `Buchhalter` | executable `buchhalter` | SwiftUI, AppKit (Mac-only files), BuchhalterCore | The Mac app: `App`, scenes, menus, `Settings`, views |
| `BuchhalterCoreTests` | Swift Testing | BuchhalterCore | One test file per core area, against in-memory containers |

`Package.swift` uses a Swift 6 tools version with the Swift 6 language mode (strict concurrency) and platforms `.macOS("27.0")`, plus `.iOS("27.0")` for the core from the start, so nothing Mac-only creeps into it.

When phase 2 or 3 starts, an Xcode project joins the repo. It references the local package for `BuchhalterCore`, holds the macOS and iOS app targets with their entitlements, and the views both apps share move into a `BuchhalterUI` library in the package. Until then the SwiftPM executable is the app, built like swell and fluff.

## Layout

**Direction.**

```
Package.swift
Makefile
Resources/              Info.plist, app icon
Sources/
  BuchhalterCore/
    Model/              @Model types, SchemaV1…, migration plan
    Store/              container setup, store location, operations
    Logic/              ISBN, statistics, search, import/export
  Buchhalter/
    App/                App, scenes, commands (menus)
    Views/              shared-ready views (no AppKit)
    Mac/                Mac-only code
Tests/
  BuchhalterCoreTests/
docs/dev/               this doc
specs/planned/, specs/done/
```

## Data model

**Direction.** The starting shape. The first spec that stores books fixes it in `SchemaV1`.

| Type | Holds | Relationships |
|---|---|---|
| `Book` | Title, subtitle, ISBN-13 (optional), publisher, year, page count, language, cover image (external storage), added date | authors (many-to-many), readings (one-to-many, cascade), shelves (many-to-many) |
| `Author` | Name, sort name ("Mann, Thomas") | books |
| `Reading` | One read-through of a book: status (`wantToRead`, `reading`, `finished`, `abandoned`), started and finished dates, rating (1–5, optional), notes | book |
| `Shelf` | A user-made collection ("Owned", "Lent out", "2027"), name, order | books |

A book read twice has two readings. "Currently reading", "Want to read" and "Read in 2026" are queries over readings, not stored lists.

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
- **Background work:** imports and metadata lookups run in a `@ModelActor` with its own context and save in batches. Model objects never cross actors; `PersistentIdentifier`s do.
- **Threading:** the main context and everything that touches the UI are `@MainActor`.

## UI structure

**Direction.** Each feature's design artifact decides the actual screens.

- **Mac:** one main window with a `NavigationSplitView`: a sidebar (Reading, Want to Read, Read, Shelves, All Books), a list or grid of books in the middle, and the book's detail with its readings on the right. Adding a book is a sheet. Menus and keyboard shortcuts for the common actions, a `Settings` scene.
- **iOS:** the same `NavigationSplitView` collapses to a stack on iPhone. Views that need a different layout on a small screen get a size-class branch, not a separate copy.

## External services

**Direction.** Looking up a book's data and cover by ISBN or title (for example Open Library) is a likely early feature. It sits behind a protocol in `BuchhalterCore`, with a fake in tests, and is never required: every field can be typed in by hand. Barcode scanning comes with the iOS app.

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
5. **Readings separate from books.** Rereads, abandoned books and "read in year X" fall out of the model instead of needing special fields.

## Open points

- The Apple Developer team, CloudKit container id and final bundle id for phase 2.
- Which metadata service to use, if any, and whether covers are downloaded or only linked.
- Import from an existing list (Goodreads CSV, a spreadsheet), if the user has one.
