# Synopsis — Plan

## Current State (audited 2026-11-18)

- **Model:** `SchemaV2` is current (`Model/SchemaV2.swift`, 138 lines). `ModelTypes.swift` aliases `Book` etc. to `SchemaV2`. `LibraryMigrationPlan` has `[SchemaV1, SchemaV2]` and one custom stage. `Book` has no text field beyond title, subtitle, publisher, origin note. CloudKit Production holds the V2 record types, deployed 2026-11-16 (sync.md, CloudKit schema).
- **Draft and operations:** `BookDraft` (`Logic/BookDraft.swift`) has no synopsis. `Library.addBook`, `updateBook`, `updateDetails` apply a draft through `BookOperations.apply`; `setCover` is the model for a one-field operation ("Change Cover" undo step). `LibrarySnapshot.BookRecord` lists the fields undo restores.
- **Lookup:** `LookupRecord` (`Lookup/LookupTypes.swift`) carries data and `CoverReference`s; services fetch covers lazily through `BookLookupService.coverData(for:size:)`. `BookLookup.run` returns the first source's match; `findCover` walks queries × services, at most 5 candidates each (`maximumCandidates`), skipping unreachable sources and throwing `noSourceReached` only when none answered. `LookupResult.merge` (`Lookup/LookupMerge.swift`) fills empty fields and offers differing ones per `LookupField` (title … isbn, cover); the banner, highlights, `use` and `undo` all work per field.
- **App:** `LookupModel.fill` downloads the cover, then merges against the current draft (generation check). `ScanCardModel` runs a `LookupModel`, so the scan card gets anything `fill` adds. Find Cover lives only in the detail's cover menu (`BookDetailView.findCover`, `isFindingCover` state); its alerts are `WindowModel.coverAlert: CoverAlert` (`noCover(suggestsGoogleBooks:)`, `noSourceReached`), shown by `FindCoverAlertModifier` (Mac file and iOS shim). `BookContextMenu` (shared) has status actions and Edit, no Find Cover. `ActiveSheet.editBook(UUID)` opens the editor.
- **Editor:** Mac `BookEditorSheet` is a `Grid` that sizes to content (ui.md, Sheets); iOS wraps it in a `NavigationStack` with a scroll view.
- **Sources, checked live 2026-11-18:**
  - DNB record field 856 with `$3 Inhaltstext`, `$q text/html`, `$u https://services.dnb.de/plus/idn/<idn>/blurb/` (fixture `dnb-isbn-piercing.xml`; 3 of the DNB fixtures have one). The page is a 1–2 KB HTML document: one `<div>` with the plain blurb, UTF-8. Field 520 `$a` holds summaries prefixed "Zusammenfassung: ", sometimes in another language and ending "--(Provided by publisher.)" (`dnb-buddenbrooks-mann.xml`).
  - Open Library: the search answer's `key` is the work ("/works/OL3511459W"). `GET https://openlibrary.org/works/<id>.json` has `description` either as a string or as `{"type": "/type/text", "value": …}`; untagged language.
  - Google Books: `volumeInfo.description` in the list answer when named in `fields` (Volume resource reference; HTML with `b`, `i`, `br`). The anonymous quota is 0, so the fixture is hand-written in the recorded answers' shape.
- Tests: 371 pass. Toolchain Xcode 27.2, Swift 6.4.2; no packages.

## Research

- SwiftData lightweight migration covers an added optional attribute; CloudKit accepts additive fields once deployed. Production rejects unknown fields from a client, so `make cloudkit-schema` and "Deploy Schema Changes" must run before a build with SchemaV3 reaches the library (sync.md).
- An app on SchemaV2 (an older iPhone build) ignores the new CloudKit fields and only writes the fields it changes, so a synopsis survives edits there.
- HTML to text: `NSAttributedString(html:)` needs AppKit/UIKit and the main thread; a small tag stripper in the core is enough for the three shapes above (`<br>`, `<p>`, `<div>`, `<b>`, `<i>`, entities).

## Decisions

1. **SchemaV3 with `Book.synopsis: String?` and `Book.synopsisSourceRaw: String?`.** The source (a `LookupSource` raw value, nil when typed or edited) drives the "From …" line. Alternative: storing the text in `originNote` or a JSON blob; rejected, the field is user-visible and edited. V2 → V3 is a lightweight stage. **Irreversible** for the library once a V3 build opens it.
2. **The text's language is the record's language (user's choice: trust the edition tag).** DNB blurb, DNB 520 and Google descriptions take `record.language`; Open Library work text counts as unknown. No NaturalLanguage framework.
3. **Synopses are fetched lazily, like covers.** `LookupRecord.synopsis: SynopsisReference?` (`.text(String)`, `.dnbBlurb(URL)`, `.openLibraryWork(key:)`) and `BookLookupService.synopsis(for:) async -> String?` (nil on any failure). Searches stay one request; a text is fetched only for the record that is used.
4. **One search routine for Complete and Find Synopsis: `BookLookup.findSynopsis`.** It tries the chosen record first (Complete), then queries × services like `findCover`, at most 3 candidates per source and query. The first text in the book's language returns at once; the first text in another or unknown language is kept as a fallback and returned at the end. A book without a language takes the first text.
5. **The synopsis is a `LookupField`.** Merge, banner count, highlight (the tab or row dot), offer ("Show · Use") and banner Undo come from the existing per-field machinery. `same` compares whitespace-collapsed, folded text.
6. **Typing clears the source.** The editor's binding sets `synopsisSource = nil` whenever the text changes; `use(.synopsis)` sets it from the result. The core stores a source only with a non-empty text.
7. **Find alerts become one enum.** `CoverAlert` → `FindAlert` with `noCover(suggestsGoogleBooks:)`, `noSynopsis(suggestsGoogleBooks:)`, `noSourceReached(FindKind)`; both modifiers switch on it. A second parallel alert state would duplicate the modifier.
8. **Find Synopsis runs from a shared finder.** `BookFinder` (`App/BookFinder.swift`, `@MainActor @Observable`, one per window, in the environment) holds the running book ids and does Find Synopsis for the cover menu and `BookContextMenu`. Find Cover stays where it is.
9. **Mac editor tabs are a segmented `Picker`, not `TabView`.** A `TabView` in a sheet draws a boxed tab style that does not match the design; the picker sits under the hint line, and the Synopsis pane takes the Details pane's measured height so the sheet keeps its size.

## Components

### Core

- **`SchemaV3`** (new): a copy of `SchemaV2`'s six models plus the two `Book` attributes. `ModelTypes` aliases move to V3; `LibraryMigrationPlan` gets `[V1, V2, V3]` and `MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)`.
- **`BookDraft`**: `synopsis: String = ""`, `synopsisSource: LookupSource?`; `init(book:)` reads both. `BookOperations.apply` writes trimmed text or nil, and the source only with text.
- **`Library.setSynopsis(_ text: String?, source: LookupSource?, for book:)`**: one undo step, "Find Synopsis" when setting, "Remove Synopsis" when clearing. `BookRecord` and its `apply` gain both fields.
- **`SynopsisReference`** and **`LookupRecord.synopsis`**, **`BookLookupService.synopsis(for:)`** with a protocol extension that returns `.text` as is and nil otherwise.
- **`SynopsisText`** (new, `Lookup/SynopsisText.swift`): `plain(fromHTML:) -> String` (block tags and `<br>` to newlines, other tags dropped, entities decoded, runs of spaces collapsed, at most one empty line between paragraphs) and `cleanedSummary(_:)` for DNB 520 (drops the "Zusammenfassung: " prefix and a trailing "--(Provided by publisher.)"). Empty results are nil.
- **`DNBRecordMapper`**: 856 with `$3` "Inhaltstext" and a `$u` on `services.dnb.de` → `.dnbBlurb`; otherwise the first 520 `$a` → `.text`. **`DNBService.synopsis`**: GET the blurb URL (15 s, 200, HTML), `SynopsisText.plain`.
- **`OpenLibraryService`**: every record gets `.openLibraryWork(key: work.key)`; `synopsis` fetches `/works/<id>.json` and decodes `description` as string or `{value}`.
- **`GoogleBooksService`**: `description` joins the `volumeInfo(...)` fields list; the mapper sets `.text(SynopsisText.plain(fromHTML:))`.
- **`Synopsis`** value (`text`, `source`). **`BookLookup.findSynopsis(_ queries:, first: LookupRecord?, bookLanguage: String?) async throws -> Synopsis?`** (`@concurrent`), Decision 4. Throws `noSourceReached` when no source answered; Complete swallows errors.
- **`LookupField.synopsis`**: `merge(_:authors:cover:synopsis:into:)` gains the synopsis; `isEmpty`, `same`, `copy` (text and source together), `offerValue` (the text) handle it. `LookupMessages` names the source for the offer line.

### App (shared)

- **`LookupModel.fill`**: runs `lookup.cover(for:)` and `lookup.findSynopsis([], first: record, bookLanguage:)` concurrently (`async let`), the language being the record's or the draft's. Then merges both. The generation check stays after both.
- **`SynopsisSection`** (new, `Views/Detail/SynopsisSection.swift`): heading "Synopsis", text in `Theme.serif` (14 Mac, 16 iOS), `lineLimit(4)` until expanded, `More`/`Less` only when the full text is taller than four lines (measured with a hidden unlimited copy), the source line from `ScanMessages`-style `SynopsisMessages.from(source)`. iOS: `contextMenu` with Copy, Edit… (`model.sheet = .editBook(id, tab: .synopsis)`), Remove Synopsis. Hidden when the book has no synopsis. Placed in `BookDetailView` between header and Collections.
- **`BookEditorSheet`**: `EditorTab { details, synopsis }`. Mac: segmented picker under the hint, the dot on "Synopsis" when `result.isHighlighted(.synopsis)` or `showsOffer(.synopsis)`. iOS: a row after ISBN pushing `SynopsisPage` (new, `Views/Sheets/SynopsisEditor.swift`, shared with the Mac pane): `TextEditor`, source line, offer banner with Show/Use, Remove Synopsis (Mac button, iOS ⋯ menu).
- **`ActiveSheet.editBook(UUID, tab: EditorTab = .details)`**: callers keep the default.
- **`BookFinder`** (new): `findSynopsis(for book:, lookup:, sources:, library:, model:)`, `isFinding(book.id)`. Saves only if the book still has no synopsis. Sets `model.findAlert`.
- **`BookContextMenu`** and the detail's cover menu: "Find Synopsis" when `book.synopsis == nil`, disabled while running or when no source is on.
- **`WindowModel`**: `coverAlert` → `findAlert: FindAlert?`.

### Mac and iOS files

- `Mac/FindCoverAlertModifier.swift` and `iOS/Buchhalter/PlatformShims.swift` (`FindCoverAlertModifier`): titles and messages for the three cases; the synopsis variants mirror the cover texts.

## Interactions

**Complete.** Editor → `LookupModel.start` → `BookLookup.run` (off main) → single record or chosen edition → `fill`: `async let cover`, `async let synopsis = findSynopsis(first: record)` (record's own reference first, then other sources per query) → main actor: generation check → `merge(record, cover:, synopsis:)` → draft and `LookupResult` → tab dot, banner count. Save → `updateBook` / `addBook` stores the text and source in one undo step.

**Use an offer.** `LookupModel.use(.synopsis)` → draft text and source from `proposed`.

**Find Synopsis.** Menu → `BookFinder.findSynopsis` (main) → `LookupQuery.coverQueries(for: BookDraft(book:))` → `findSynopsis(queries, first: nil, bookLanguage: book.language)` (off main) → nil: `findAlert = .noSynopsis(suggestsGoogleBooks: sources.suggestsGoogleBooks)`; `noSourceReached`: `.noSourceReached(.synopsis)`; text: if `book.synopsis == nil`, `library.setSynopsis(text, source:)`.

**Scan.** `ScanCardModel` → `LookupModel.fill` → the draft carries the synopsis → Add and Scan Next → `addBook`.

**Sync.** Two new fields on `CD_Book`; deployed before the build reaches the library (Testing, step order).

## Changes by file

| File | New/changed | What |
|---|---|---|
| `Sources/BuchhalterCore/Model/SchemaV3.swift` | new | V2 models plus `synopsis`, `synopsisSourceRaw` |
| `Sources/BuchhalterCore/Model/ModelTypes.swift` | changed | Aliases to V3 |
| `Sources/BuchhalterCore/Model/LibraryMigrationPlan.swift` | changed | V3 and the lightweight stage |
| `Sources/BuchhalterCore/Model/Book+Derived.swift` | changed | `synopsisSource: LookupSource?` accessor |
| `Sources/BuchhalterCore/Logic/BookDraft.swift` | changed | Two fields, `init(book:)` |
| `Sources/BuchhalterCore/Store/BookOperations.swift` | changed | `apply` writes them; `setSynopsis` |
| `Sources/BuchhalterCore/Store/LibrarySnapshot.swift` | changed | `BookRecord` fields and `apply` |
| `Sources/BuchhalterCore/Lookup/LookupTypes.swift` | changed | `SynopsisReference`, `LookupRecord.synopsis`, `Synopsis` |
| `Sources/BuchhalterCore/Lookup/BookLookupService.swift` | changed | `synopsis(for:)` and default |
| `Sources/BuchhalterCore/Lookup/SynopsisText.swift` | new | HTML to plain text, 520 cleanup |
| `Sources/BuchhalterCore/Lookup/DNBRecordMapper.swift` | changed | 856 Inhaltstext, 520 |
| `Sources/BuchhalterCore/Lookup/DNBService.swift` | changed | Blurb download |
| `Sources/BuchhalterCore/Lookup/OpenLibraryService.swift` | changed | Work reference, work description |
| `Sources/BuchhalterCore/Lookup/GoogleBooksService.swift` | changed | `description` in `fields` |
| `Sources/BuchhalterCore/Lookup/GoogleBooksRecordMapper.swift` | changed | Description → `.text` |
| `Sources/BuchhalterCore/Lookup/BookLookup.swift` | changed | `findSynopsis` |
| `Sources/BuchhalterCore/Lookup/LookupMerge.swift` | changed | `LookupField.synopsis`, merge parameter |
| `Sources/BuchhalterCore/Lookup/LookupMessages.swift` | changed | Source line, offer line, alert texts |
| `Sources/Buchhalter/App/WindowModel.swift` | changed | `FindAlert`, `editBook(_, tab:)` |
| `Sources/Buchhalter/App/BookFinder.swift` | new | Find Synopsis state and flow |
| `Sources/Buchhalter/Views/Sheets/Lookup/LookupModel.swift` | changed | Synopsis in `fill` |
| `Sources/Buchhalter/Views/Sheets/BookEditorSheet.swift` | changed | Tabs (Mac), row (iOS), initial tab |
| `Sources/Buchhalter/Views/Sheets/SynopsisEditor.swift` | new | Pane and page |
| `Sources/Buchhalter/Views/Detail/SynopsisSection.swift` | new | Detail section |
| `Sources/Buchhalter/Views/Detail/BookDetailView.swift` | changed | Section, cover menu item |
| `Sources/Buchhalter/Views/Books/BookContextMenu.swift` | changed | Find Synopsis |
| `Sources/Buchhalter/Views/RootView.swift` | changed | `BookFinder` in the environment |
| `Sources/Buchhalter/Mac/FindCoverAlertModifier.swift` | changed | `FindAlert` cases |
| `iOS/Buchhalter/PlatformShims.swift` | changed | `FindAlert` cases |
| `Resources/Localizable.xcstrings` | changed | New keys, English and German (`make strings`) |
| `Tests/BuchhalterCoreTests/Fixtures/dnb-blurb-piercing.html` | new | The live blurb page, recorded |
| `Tests/BuchhalterCoreTests/Fixtures/openlibrary-work-stoner.json` | new | `/works/OL3511459W.json`, recorded |
| `Tests/BuchhalterCoreTests/Fixtures/googlebooks-description.json` | new | Hand-written list answer with `description` |
| `Tests/BuchhalterCoreTests/SynopsisTests.swift` | new | See Testing |
| `Tests/BuchhalterCoreTests/MigrationTests.swift` | changed | V2 → V3 |
| `Tests/BuchhalterCoreTests/LookupMergeTests.swift` | changed | Synopsis field |
| `Tests/BuchhalterCoreTests/UndoTests.swift` | changed | Synopsis fields, `setSynopsis` |
| `docs/dev/architecture.md`, `docs/dev/lookup.md`, `docs/dev/ui.md`, `docs/dev/sync.md` | changed | At archive time |

## Testing

Unit tests (`swift test`):

- `SynopsisText`: the DNB blurb fixture becomes its one paragraph; `<br><br>` and `<p>` give paragraphs; `&amp;`, `&quot;`, `&#8217;` decode; the 520 prefix and "(Provided by publisher.)" go; whitespace-only gives nil.
- Mappers: Piercing's record has `.dnbBlurb` with the services.dnb.de URL; a record without 856 but with 520 has `.text`; Open Library records carry the work key; the Google fixture's description becomes plain text.
- Services against `FakeHTTPClient`: DNB blurb download (200, non-200, timeout → nil); Open Library description as string and as `{value}`; missing description → nil.
- `findSynopsis` with fake services: the first record's own text in the book's language returns without asking others; a German book skips an English text from the first source and takes the German one from the second; only an English text → it is returned; Open Library (unknown language) loses to a tagged match and wins when alone; all unreachable → `noSourceReached`; nothing → nil; at most 3 candidates per source and query.
- Merge: empty synopsis is filled and counted; an equal text (whitespace, case) is neither filled nor offered; a different text is offered; `use` copies text and source; banner `undo` clears it.
- Draft and operations: `addBook` and `updateBook` store text and source; editing the text in a draft with no source stores nil; `setSynopsis` is one undo step that restores the old text and source.
- `MigrationTests`: a V2 store in a temporary folder opens as V3 with the books intact and `synopsis` nil.
- The catalog test covers the new keys.

Builds: `swift build`, `make app`, `make ios-sim`.

**Schema step, before any V3 build reaches the library:** the agent runs `make cloudkit-schema` and `build/BuchhalterSchema.app/Contents/MacOS/Buchhalter -initializeCloudKitSchema YES` (Development, scratch store) and checks for `cloudkit-schema: ok`. Then the user deploys in the CloudKit Console and confirms `CD_Book` lists `CD_synopsis` and `CD_synopsisSourceRaw` in Production. Only then the user starts the new `make app` build and runs `make ios-install`.

Manual checks for the user (Mac, then iPhone; once in German):

1. Edit a German book with an ISBN and no synopsis, Complete: the Synopsis tab has the dot, the text, "From the Deutsche Nationalbibliothek"; the banner counts it. Save; the detail shows 4 lines and More.
2. More and Less unfold and fold; a short synopsis has no More.
3. An English book via Complete gets "From Google Books" or "From Open Library".
4. Type your own synopsis on a book, Complete: your text stays, the offer line appears; Use replaces it; the source line follows.
5. Find Synopsis from the row menu and the cover menu; ⌘Z removes it. A book no source knows → "No synopsis found".
6. Wi-Fi off, Find Synopsis → "Can't reach any book source".
7. Remove Synopsis in the editor and (iPhone) by long press; the section disappears.
8. iPhone editor: the Synopsis row, the page, back to the editor; Save keeps the text.
9. Scan a book on the iPhone: the card looks as before; the added book has a synopsis.
10. A synopsis added on the Mac shows on the iPhone.
11. The Mac Details tab looks as before; switching tabs keeps the sheet size.

## Permissions

| Action | Status |
|---|---|
| `swift build`, `swift test` | allowed (`.claude/settings.json`) |
| `make app`, `make cloudkit-schema`, `make strings`, `make ios-sim` | allowed (`Bash(make:*)`) |
| `xcodebuild` (inside make) | allowed (`.claude/settings.local.json`) |
| Running `build/BuchhalterSchema.app/Contents/MacOS/Buchhalter -initializeCloudKitSchema YES` | prompts; the user chose: the agent runs it, approving the prompt |
| `curl` to record the DNB and Open Library fixtures | prompts; approve per call |
| Deploy Schema Changes in the CloudKit Console | the user does it |
| `make ios-install`, starting the Mac app | the user does it, after the deploy |

## Risks and open points

- **Order of the schema step:** a V3 build syncing before the deploy gets CloudKit errors on every export of a book (the sync line shows a problem). The implementer stops after the initializer and waits for the user's deploy confirmation.
- **Old iOS build:** a SchemaV2 iPhone build keeps working and ignores the fields; install the new one soon after.
- **DNB blurb rights:** the texts are the publishers'. Fine for a personal library; check MVB's terms before a store release.
- **Request count:** Complete adds one request (the record's own text) in the common case and up to `queries × sources × 3` when the language rule falls through. The cover and synopsis downloads run concurrently, so the banner should not appear noticeably later; watch it on a slow network.
- **Measuring truncation** in `SynopsisSection` must not trigger layout loops; use `onGeometryChange` on a hidden copy, not `GeometryReader` writing state in `body`.
- **Mac sheet height:** if measuring the Details pane is unreliable on first open, a fixed minimum height for the Synopsis pane (450 pt) is acceptable.
