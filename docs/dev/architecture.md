# Architecture

Buchhalter is a SwiftUI app over a SwiftData store of books and readings, on the Mac and as one iOS app for iPhone and iPad. Both apps share the core library and the views, and one library through iCloud (CloudKit). The UI is in English and German.

This doc is the overview every change starts from. Each area has its own doc; read it when you change that area:

| Doc | Covers |
|---|---|
| [ui.md](ui.md) | Visual language, the app's own controls, sheets, the book detail, the Mac window and its saved state, the iPhone and iPad layout |
| [sync.md](sync.md) | Store locations, iCloud sync on and off, the copy of the library from before sync, the CloudKit schema, sync status, sync duplicates |
| [lookup.md](lookup.md) | Book lookup (Complete, Find Cover, Find Synopsis), the three sources, synopses, Google Books and its key |
| [scanning.md](scanning.md) | Barcode scanning on the Mac and on iOS: reading, the scan logic, the camera, the flows |

## Apps and signing

- **Mac:** the SwiftPM executable, sandboxed, signed by `make app` with "Apple Development" and the macOS App Development profile at `~/Library/Developer/Buchhalter/Buchhalter_Development.provisionprofile` (not in the repo; it lists this Mac and expires on 2027-11-16).
- **iPhone and iPad:** one iOS 27 target in `iOS/Buchhalter.xcodeproj`, automatic signing; Xcode manages the profile and registers each device on its first build (Developer Mode on).
- Bundle id `de.juergenalbertsen.buchhalter`, team `3PT9KVM9AJ`, container `iCloud.de.juergenalbertsen.buchhalter`, CloudKit Production for both.

## Targets

| Target | Kind | Imports | Contents |
|---|---|---|---|
| `BuchhalterCore` | library | Foundation, SwiftData, ImageIO | The `@Model` types, schemas and migration plan, container setup, `Library` with every operation that changes data (books, readings, collections, list settings) and its undo, and the pure logic: ISBN, names, folding, sorting, search, lists, drafts, duplicates, covers, formatting, book lookup, scan logic, sync status. Texts come from the app's catalog. Fully unit-tested |
| `BuchhalterKeychain` | library product | Foundation, Security, BuchhalterCore | `KeychainSecretStore` for the Google Books key, behind the core's `SecretStore` protocol. Its own target so the core stays Foundation and SwiftData only |
| `Buchhalter` | executable `buchhalter` | SwiftUI, AVFoundation, Vision, CloudKit, Core Data, AppKit (Mac-only files), both libraries | The Mac app: `Mac/` plus the shared `App/` and `Views/`. `@MainActor` by default (`defaultIsolation`) |
| `Buchhalter` (Xcode) | iOS app, iPhone and iPad | SwiftUI, UIKit, PhotosUI, AVFoundation, Vision, CloudKit, both libraries through a local package reference | `iOS/Buchhalter/` plus `Sources/Buchhalter/App` and `Sources/Buchhalter/Views` as synchronized folders, never `Mac/`. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, device family 1,2 |
| `BuchhalterCLI` | executable `buchhalter-cli` | Foundation, AppKit, SwiftData, both libraries | Maintenance on the library, English only, Mac only. `find-covers` runs Find Cover for every book without one (`--report`, `--limit`, `--dry-run`). It works on `~/Library/Application Support/Buchhalter/` (the library from before sync; `$BUCHHALTER_HOME` overrides it) and refuses to run while the app is open |
| `BuchhalterCoreTests` | Swift Testing | BuchhalterCore | One file per core area, against in-memory containers; `Fixtures/` holds recorded source answers, read through `#filePath` |

`Package.swift`: tools version 6.2, Swift 6 language mode, platforms `.macOS("27.0")` and `.iOS("27.0")` (so nothing Mac-only creeps into the core), no package resources.

**Platform code** sits in `Sources/Buchhalter/Mac/` (only in the package), in `iOS/Buchhalter/` (only in the Xcode target), or behind `#if os(macOS)` / `#if os(iOS)` in a shared file when it is a line or two. Longer differences are a view or modifier with the same name in both platform folders (`librarySubtitle`, `FindCoverAlertModifier` (Find Cover's and Find Synopsis's alerts), `CameraPreviewLayer`, `ScanFeedback.mac` and `.phone`). `Views/Common/PlatformStyles.swift` maps Mac-only styles (`.link`, `.checkbox`, `onDeleteCommand`, sheet and pane widths) onto iOS.

## Layout

```
Package.swift, Makefile
Resources/        Mac Info.plist, the entitlements template, Localizable.xcstrings, InfoPlist.xcstrings, AppIcon.icns, PoweredByGoogle.png
Scripts/          make-icon.swift, make-isbn-ranges.swift
Sources/
  BuchhalterCore/ Model/, Store/, Sync/, Logic/, Scan/, Lookup/
  BuchhalterKeychain/
  BuchhalterCLI/
  Buchhalter/
    App/          shared: WindowModel, BookSources, BarcodeCamera, FrameReader, CloudSyncMonitor, SyncActions
    Views/        shared: Sidebar, Toolbar, Books, Detail, Sheets (Lookup/, Scan/), Settings, Common
    Mac/          Mac-only: BuchhalterMacApp (@main), AppDelegate, menus, Settings scene, window state, camera preview, sync setup and the copy from the old library
iOS/
  Buchhalter.xcodeproj, Info.plist, Buchhalter.entitlements, Assets.xcassets
  Buchhalter/     iOS-only: BuchhalterPhoneApp (@main), PhoneUI, PhoneRootChrome, PhoneSettingsView, PlatformShims, PhotoCapture, DebugLaunch, Scan/
Tests/BuchhalterCoreTests/
docs/dev/         this doc and the area docs
specs/planned/, specs/done/
```

## Data model

`SchemaV3`.

| Type | Holds | Relationships |
|---|---|---|
| `Book` | `id`, title, subtitle, `isbn13` (digits, for matching and search), `isbnText` (display; a valid ISBN is stored hyphenated as ISBN-13), publisher, year, page count, language and original language (ISO 639; the original only for a translation), cover image (external storage, JPEG, longest side 1200 px), added date, origin (`manual`, `lookup`, `scan`, `assistant`), origin note (the lookup record id, "dnb:991442512"), synopsis (plain text, paragraphs kept), synopsis source (`LookupSource` raw value; nil when typed or edited) | authorships (cascade), readings (cascade), collections (many-to-many, nullify) |
| `Author` | `id`, name, sort name ("Mann, Thomas"). One per name, reused across books, kept when it has no books left | authorships (cascade) |
| `Authorship` | `id`, position. The ordered join: SwiftData's to-many relationships are unordered, and the first author decides the sort order | book, author |
| `Reading` | One read-through: `id`, status (`wantToRead`, `reading`, `finished`, `abandoned`), started, ended, `stars` (0.5–5.0 in halves, optional), notes, created. `rating` is SchemaV1's whole-star field, copied into `stars` by the migration and unused since. The current reading is the one created last | book |
| `Collection` | A user-made list: `id`, name, note, sort index, created | books, settings (cascade) |
| `ListSettings` | Sort levels ("author:asc,year:asc", empty for the default) and view mode (`list`, `grid`) of one list, by `key` (`reading`, `wantToRead`, `read`, `all`) or hanging off a collection. The row `sidebarOrder` holds the order of the built-in lists. The row `sort` is one sort for every list, which an older app version writes: while it exists every list shows its sort, and `Library.adoptGlobalSort` (at launch, after each iCloud import, before a sort change) copies it into every list and deletes it, so older per-list values never come back. No unique constraint, so readers take the newest `updatedAt` | collection |

A book read twice has two readings. Reading, Want to Read and Read are computed from each book's current reading, not stored. A book without a reading is valid and shows in All Books and its collections. Clearing the status in Edit Book deletes the current reading; earlier readings stay, and an abandoned current reading is left alone. Collections hold any books in any status; a book can be in several.

**CloudKit rules:**

- Every attribute is optional or has a default value. Enums are stored as their `String` raw value, so an unknown value from a newer version does not break decoding.
- No `@Attribute(.unique)`. Duplicates are prevented in the operations and merged after a sync ([sync.md](sync.md)).
- Every relationship is optional and has an inverse. No `.deny` delete rules.
- Large data (covers) uses `@Attribute(.externalStorage)`.
- Schema changes are additive only and go through a new `VersionedSchema` in the one `SchemaMigrationPlan`, then `make cloudkit-schema` and "Deploy Schema Changes…" ([sync.md](sync.md)) before a build with it reaches the library. The V1 → V2 stage adds `Reading.stars` and copies `rating` into it in `didMigrate`; V2 → V3 is lightweight and adds `Book.synopsis` and `Book.synopsisSourceRaw`. `MigrationTests` and `SynopsisStoreTests` run them on old stores.

## Data flow

- **Reading:** views use `@Query`. `BuchhalterCore` filters, searches and sorts the fetched arrays in memory (`LibraryLists`, `BookSearch`, `BookSorter`): `#Predicate` and `SortDescriptor` cannot do German collation with diacritic folding, sort by the first author, skip leading articles or express "the latest reading is finished". Lists update by themselves, including after a sync.
- **Writing:** views call operations on `Library` on the main `ModelContext`. The operations hold the rules (a finished reading has a finished date and an optional half-star rating, collection names are unique, one reading is current) and are what the tests cover. Views never set model properties.
- **Undo:** SwiftData's undo is not used: on macOS 27.2 it reverts an attribute change in memory without marking the context dirty, so the undone value is never saved. `Library.change` snapshots the library before and after each operation, saves, and registers undo and redo closures with the window's `UndoManager`; a closure writes only the fields that differ, so a field another device changed meanwhile survives (`UndoSyncTests`). One user action is one undo step with an action name. Sort and view changes are saved without an undo step. A new model field must be added to its record in `LibrarySnapshot.swift` and to `apply`; `UndoTests` and `UndoPersistenceTests` check the fields.
- **Threading:** the main context and the UI are `@MainActor`. Network work, parsing and cover normalizing run `@concurrent` and hand back value types only; model objects never cross actors.

## Localization

- English (development language) and German. The app follows the system language, or the per-app language in System Settings.
- **One String Catalog,** `Resources/Localizable.xcstrings`, for the apps and the core, in the main bundle: AppKit's menus and the language choice follow the main bundle's `.lproj` folders, and SwiftPM's `Bundle.module` handles catalogs unreliably. `make app` compiles it with `xcstringstool`; the Xcode target has it as a resource. `Text`, `String(localized:)` and `LocalizedStringResource` take no `bundle:` argument. In the test runner core texts fall back to the English key.
- Keys are the English text. Where one English text needs two German ones, the key is semantic with a default value (`sortField.finished`). `LocalizationCatalogTests` fails on a missing or untranslated value, a plural without `one` or `other`, and German terms that differ from the specs.
- **`make strings`** emits `.stringsdata` from the compiler for the package and the iOS target (`-emit-localized-strings` in `OTHER_SWIFT_FLAGS`; `SWIFT_EMIT_LOC_STRINGS` would let Xcode rewrite the catalog with the iOS texts alone) and syncs them into the catalog. Every key is a literal at its call site.
- Dates, numbers, ratings and counts go through `BookFormatting` with an explicit `Locale`; plurals through the catalog. Years print without grouping. No concatenated texts.
- `Resources/InfoPlist.xcstrings` holds the camera prompt.
- Book data is never translated. Sorting and search use German collation (`de_DE`), case- and diacritic-insensitive, in every UI language.
- `-AppleLanguages '(de)'` changes the language, not the region; German date formats also need `-AppleLocale de_DE`.

## Build and test

| Command | Result |
|---|---|
| `make` / `make build` | `swift build -c release` → `.build/release/buchhalter` |
| `make app` | `build/Buchhalter.app`: binary, Info.plist, icon, compiled catalogs, the profile, signed with the entitlements from the template (CloudKit Production). Fails when the profile (`PROFILE`) is missing |
| `make cloudkit-schema` | `build/BuchhalterSchema.app`, CloudKit Development, only for initializing the schema ([sync.md](sync.md)) |
| `make install` | Copies the bundle to `/Applications/Buchhalter.app`. Only on the user's request |
| `make cli` | `build/buchhalter-cli`; the user runs it with Buchhalter closed |
| `make ios` | `xcodebuild` Release for `DEVICE` (default `jaPhone`, the name in `xcrun devicectl list devices`) with `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` → `build/ios/Buchhalter.app` |
| `make ios-install` | `make ios`, then installs on `DEVICE` (`DEVICE=jaPad`). The device must be unlocked. Only on the user's request |
| `make ios-sim` | Unsigned Debug build for the simulator; compiles everything the device build does |
| `make test` / `swift test` | The core tests, including the catalog test |
| `make strings` | Syncs the texts of both apps into the catalog |
| `make isbn-ranges` | Downloads the ISBN range message and regenerates `Logic/ISBNRanges.swift` (committed) |
| `make icon` | Redraws `Resources/AppIcon.icns` (full-bleed and opaque, so macOS masks it to its rounded square) |

The user starts the apps: `open build/Buchhalter.app` runs on the real library (German: `--args -AppleLanguages '(de)' -AppleLocale de_DE`), and the iOS app on their devices. Agents build and do not start them. A separate Mac store, which never syncs, needs `open --env BUCHHALTER_HOME=<folder> build/Buchhalter.app` or the binary run directly with stderr redirected; `open` passes no environment and shows no stderr.

Agents may run `make ios-sim` builds in the simulator, whose store is never the library. Debug builds read two launch arguments there (`DebugLaunch.swift`): `-debugSeed YES` fills an empty store with sample books, `-debugScreen list|book|addBook|settings` opens that screen.

## Decisions

Area decisions are in the area docs.

1. **SwiftData, not SQLite or JSON files.** It gives `@Query`-driven UI, migrations and CloudKit mirroring. An own SQLite layer, as in fluff, would mean building sync by hand.
2. **SwiftPM and `make` for the Mac, an Xcode project only for iOS.** Agents and the user build and test from the command line, like swell and fluff; `make app` embeds the profile and signs itself. An iOS app needs a project; `make ios` drives it with `xcodebuild`.
3. **CloudKit rules from day one.** Cheaper than migrating the model's shape when sync started.
4. **Rules live in core operations, views stay thin.** Testable against an in-memory container without a display, and both apps get them.
5. **English and German from the first feature, in String Catalogs.** Each feature carries both languages and the tests catch gaps.
6. **Readings separate from books.** Rereads, abandoned books and "read in year X" fall out of the model.
7. **Collections are the user's lists, statuses are queries.** Reading, Want to Read and Read never need maintaining.
8. **External services behind protocols, never required.** Each service has a fake, so tests run offline and the app works without network or keys.
9. **One String Catalog in the main bundle.** Per-target catalogs resolve through `Bundle.module`, unreliable under `swift build`, and leave AppKit without a `de.lproj`.
10. **Lists, filtering, sorting and search in the core over fetched arrays.** One in-memory rule keeps lists and counts consistent where `#Predicate` cannot express them.
11. **Ordered authors through an `Authorship` join, one `Author` per name.** The first author decides the sort order; a corrected sort name applies to all of an author's books.
12. **`Library` does the undo, from value snapshots.** SwiftData's undo does not persist attribute changes on macOS 27.2. One mechanism, one step per user action.
13. **Sort and view choices are data, not undo steps.** A sort and a view mode per list, in `ListSettings`, so they sync.
14. **Half stars as a new attribute, not a changed one.** A type change is not allowed with CloudKit; an additive `stars` plus one copy in `didMigrate` keeps the old value.
15. **ISBN hyphens from the official range table, generated into code.** Hyphen positions depend on group and publisher. The generated table is committed: no package resources, no network at build time.
16. **The iOS target compiles the shared folders, no UI library.** A library would make about 60 views `public` and change the Mac build; compiling `App` and `Views` twice costs nothing.
17. **Automatic signing for iOS, manual for the Mac.** Xcode registers each new device; the Mac keeps the profile `make app` embeds.

## Known limitations

- The iPad in portrait cannot start with the sidebar open: `NavigationSplitView` shows the list over the detail first.
- `buchhalter-cli` works on the old folder and the `local.buchhalter` defaults, not on the synced store.
- "iCloud turned off for Buchhalter" is inferred from an available account plus a `notAuthenticated` error ([sync.md](sync.md)).
- The System Settings URL for iCloud storage (`x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings?icloud`) is not documented by Apple.
