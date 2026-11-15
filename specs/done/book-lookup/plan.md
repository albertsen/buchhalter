# Book Lookup — Plan

## Current State (audited 2026-11-15)

**Toolchain and package.** Xcode 27.2, Swift 6.4.2, macOS 27 SDK. `Package.swift` uses swift-tools-version 6.2 and the Swift 6 language mode, with platforms `.macOS("27.0")` and `.iOS("27.0")`. It has three targets:
- `BuchhalterCore`: library, Foundation + SwiftData + ImageIO, no resources.
- `Buchhalter`: executable, `.defaultIsolation(MainActor.self)`.
- `BuchhalterCoreTests`: Swift Testing.

There are no dependencies and no package resources. 106 tests pass.

**Signing and network.** The app is ad-hoc signed by `make app`, with no sandbox and no entitlements, so outgoing HTTPS works today. `Resources/Info.plist` has no ATS keys, and none are needed because both services use HTTPS.

**Localization.** There is one catalog, `Resources/Localizable.xcstrings` (158 keys). `make strings` syncs keys from the compiler's `.stringsdata`, and `make app` compiles the catalog into `Contents/Resources/{en,de}.lproj`. Core texts use `String(localized:)` / `LocalizedStringResource` against `Bundle.main`, and in tests they fall back to the English key. `LocalizationCatalogTests` covers four things:
- It reads the catalog through `#filePath`, not a bundle.
- It requires `en` and `de` values in state `translated`.
- It checks top-level `variations.plural` for `one`/`other`.
- It pins the spec's German terms.

No key uses `substitutions` yet. Existing keys this feature reuses: `Cancel` → "Abbrechen", `Save` → "Speichern", `Add Book`, `Edit Book` → "Buch bearbeiten". `Undo`, `Use`, `Stop`, `Complete` and `Try Again` do not exist yet.

**`BookEditorSheet`** (`Sources/Buchhalter/Views/Sheets/BookEditorSheet.swift`) is Add Book and Edit Book in one view:
- State: `@State draft: BookDraft`, `pendingAuthor`, `duplicates: DuplicateIndex` (built once on open), and `usedLanguages`.
- Layout: a header `Text(isEditing ? "Edit Book" : "Add Book")`, then a `ScrollView` with a `Grid` form (`fields`, a divider, `statusRows`), then the duplicate banner and a footer with Cancel and Add Book/Save.
- Width is fixed at 620. Labels use `row(_:)` with `fixedSize()` and `minWidth: 70`.
- Year and Pages share one row (an `HStack`), as do Language and Original Language.
- `save()` commits the pending author text, then calls `library.addBook(draft)` or `library.updateBook(book, with: draft)` inside `model.attempt`, then `dismiss()`.
- `duplicate` is recomputed from `draft` on every render, so filled-in values are covered automatically.

**`BookDraft`** (core) is `Equatable, Sendable`:
- Fields: `title`, `subtitle`, `authors: [AuthorDraft]` (`name`, `sortName`, `isExisting`), `yearText`, `pagesText`, `language`/`originalLanguage` (two-letter codes, e.g. "de"), `publisher`, `isbnText`, `coverData`, `status`, `startedAt`, `finishedAt`, `rating`, `notes`, `collectionIDs`.
- Derived: `issues`, `canSave`, `year`, `pages`.
- In Add Book, `language` starts as `LanguageOptions.defaultLanguage(books:)`, so it is rarely empty.

**`Library`** (`@MainActor` struct):
- `addBook(_:origin:originNote:)` and `updateBook(_:with:)` validate, then apply in one `change(...)` undo step.
- `suggestedAuthor(for:)` reuses an existing author (`AuthorName.matchKey`) with its stored sort name, or guesses one.
- `existingAuthors()` is internal.
- `apply` drops `originalLanguage` when it equals `language`.
- `originRaw` and `originNote` are already in `LibrarySnapshot` (capture, apply, diff). `originNote` is not shown anywhere in the UI.
- `BookOrigin.lookup` exists.
- SchemaV1 is in use on the user's real library and has no lookup-id attribute.

**Logic helpers in core:**
- `CoverImage.normalize(_:)` is `@concurrent async throws` and returns JPEG with a longest side of 1200 px. `CoverImage.thumbnail(from:maxPixelSize:)` exists.
- `LanguageOptions.codes(used:locale:)` offers `Locale.LanguageCode.isoLanguageCodes` filtered to two letters and to codes with a localized name.
- `BookFormatting` has `languageName`, `pageCount` (plural `%lld pages`) and `metaLine`.
- `AuthorName` has `normalize`, `matchKey` (via `TextFolding.fold`, `de_DE`, case- and diacritic-insensitive) and `guessSortName`.
- `ISBN.parse` returns `.empty/.incomplete/.valid(ISBN)/.invalid` and converts ISBN-10 to ISBN-13.

**App views:**
- `CoverPicker` takes `coverData: Binding<Data?>`, title and author, and normalizes dropped, pasted and chosen images itself.
- `AuthorField` takes `authors` and `pendingName` bindings and reads `\.library` from the environment (`Views/Common/LibraryEnvironment.swift`).
- `Theme` has `accent #1F6F5C`, `tint #DCEBE6`, `tintText #14503F` and `error #B3261E`.

**Tests.** `Tests/BuchhalterCoreTests/TestSupport.swift` provides `TestLibrary` (in-memory container, optional `UndoManager`) and `date(_:_:_:)`.

**Fixtures.** They sit in `specs/planned/book-lookup/fixtures/`, which is untracked in git.

**Design files.** Only `LookupStates.dc.html` and `LookupEditGerman.dc.html` exist in the scratchpad folder. `LookupAdd`, `LookupMatches` and `LookupFilled` are listed in its `canvas.json` but missing on disk; the implementer reads them from https://claude.ai/artifact/KWjhfRAqkfyM8d4sYB3ggT (section "Book Lookup") with the Artifact read action. The edit design shows:
- the sheet at 650 pt wide;
- filled fields with background `#EEF6F3` and border `#8FB8AD`;
- a filled cover with a 2 pt `#8FB8AD` outline;
- the banner in `#DCEBE6` / `#14503F` at 12 pt;
- offer notes at 11 pt in `#5F6670`, with the `Übernehmen` link at 11 pt in the accent colour;
- the Complete button with a 1 pt accent border, a white fill and `#14503F` semibold text.

**Spec points the facts change:**
- `007` is not a reliable print test. The Polish audio CD in `dnb-buddenbrooks-mann.xml` has `007 = "tu"`. Only `337$a = "audio"` and `300$a = "1 CD …"` mark it.
- `openlibrary-isbn-stoner.json` holds two Jean Renoir works sharing ISBN 9780940322776, not Stoner. Tests use it for that ISBN.
- Open Library's search returns no `editions.number_of_pages` for the Stoner editions (probe 2026-11-15). Pages from Open Library will usually be empty.

## Research

All findings were probed live on 2026-11-15. They hold for the installed toolchain (Swift 6.4.2, macOS 27 SDK, Foundation's `XMLParser`, `URLSession` async APIs).

**DNB SRU** (`https://services.dnb.de/sru/dnb`, `version=1.1`, `operation=searchRetrieve`, `recordSchema=MARC21-xml`):
- Access: anonymous, no key. Metadata is CC0 (https://www.dnb.de/EN/nationalbibliografie).
- Query indexes: `num=` (ISBN), `tit=` (word search), `per=` and `mat=books`, combined with ` and `. `maximumRecords=100` works and 500 fails, so the cap is 100. `numberOfRecords` gives the total (Buddenbrooks + Mann + `mat=books`: 477).
- Order: the 20 Buddenbrooks records in the fixture all come from 2025–2027, so the server's default order is newest first. This is not documented.
- Carriers: `mat=books` still returns audio carriers. Drop records whose `337$a` is audio, video, computer or online, or whose `300$a` names a carrier (CD, DVD, Online-Ressource). Drop records whose `007` is present and does not start with "t". Records without 337/338 (several printed translations) are kept.
- Title (245): `$a` title, `$b` subtitle, `$c` statement of responsibility. Non-sort markers U+0098/U+009C appear (`&#152;The&#156; Buddenbrooks`, `&#152;Der&#156; Mann, der …`), and trailing ISBD punctuation (" /", " :", " ;", " =") must be trimmed.
- Persons: 100 is the main heading, 700 holds further persons with `$4` relators (`aut`, `trl`). Headings come in forms such as "Murakami, Ryū", "Mann, Thomas,, 1875-1955", "Mann, Thomas, (1875-1955)" and "Man en" (no comma).
- Language: 041 `$a` language and `$h` original, as ISO 639-2/B. 008 positions 35–37 repeat the language.
- Publication: 264 (ind2 1 publication, 4 copyright) `$b` publisher and `$c` year, in forms "2026", "[2026]", "©2026", "© 2026", "copyright 2026", "2025.05". 260 is the fallback. 008 positions 7–10 hold the year ("081126s2009").
- Extent (300$a): "781 Seiten", "173 S.", "666 pages", "717 mian", "380 Seiten, 5 ungezählte Seiten", "1 CD (22 godz. 42 min)".
- ISBN: 020 `$a` digits and `$9` hyphenated, several per record.
- Covers: `https://portal.dnb.de/opac/mvb/cover?isbn=<isbn13>` returns `image/jpeg` 200 (`&size=s` about 4 KB, default about 47 KB, `&size=l` large), or 404 with HTML when there is none. The service is undocumented, so any failure means no cover. Covers are publishers' copyright; personal use only.

**Open Library** (https://openlibrary.org/dev/docs/api/search, https://openlibrary.org/dev/docs/api/covers):
- Search: `search.json?title=&author=&fields=…&limit=` returns works, each with `editions.docs[0]` as the best-matching edition. `search.json?isbn=` searches by ISBN.
- Formats: `editions.format` is returned ("Paperback", "audio cd"; probe 2026-11-15).
- Languages are ISO 639-2/B ("eng", "ger"). `publish_date` comes in forms "2012", "Sep 23, 2014", "September 30, 2001". `author_name` is sometimes inverted ("Renoir, Jean").
- Covers: `https://covers.openlibrary.org/b/id/<cover_i>-{S,M,L}.jpg?default=false` returns 404 without a cover.
- No key. The service asks for a User-Agent naming the app; use "Buchhalter/0.1 (personal book app)", without name or email.

**Foundation:**
- `Locale.LanguageCode("jpn").identifier(.alpha2)` returns "ja", but 639-2/B codes ("ger", "chi", "fre", "dut", "geo") return nil. A 20-entry B→T table is needed first: alb→sqi, arm→hye, baq→eus, bur→mya, chi→zho, cze→ces, dut→nld, fre→fra, geo→kat, ger→deu, gre→ell, ice→isl, mac→mkd, mao→mri, may→msa, per→fas, rum→ron, slo→slk, tib→bod, wel→cym. Verified with Swift 6.4.2.
- `XMLParser` is event-based and available on macOS and iOS, so MARC21-xml needs no dependency.
- `URLSession.data(for:)` throws on Task cancellation (`URLError.cancelled` / `CancellationError`), so Stop is `Task.cancel()`.

**SwiftUI (macOS 27 / iOS 27):**
- `List(selection:)` gives arrow-key selection.
- `.contextMenu(forSelectionType:menu:primaryAction:)` runs `primaryAction` on double-click (Mac) and tap-confirm (iOS). That is the shared way to get "double-click to use".
- `.sheet` presented from inside a sheet stacks on macOS and iOS.
- `.help(_:)` gives the tooltip on macOS and is ignored on iOS.

## Decisions

1. **DNB first, Open Library only when DNB has zero matches after filtering. A DNB failure does not fall back.** An outage shows the red DNB hint with Try Again. The alternative, falling back on failure, would quietly fill a German library from a mostly English source. The spec ties the fallback to "finds nothing", not to "cannot be reached".
2. **Two layers behind protocols: `HTTPClient` and `BookLookupService`.** The services (URL building, parsing, filtering) are tested against the real fixtures through a `FakeHTTPClient` that also checks the requested URLs. The coordinator and merge are tested with a `FakeLookupService`. The alternative, faking only `BookLookupService`, would leave the parsers and query building untested against real data.
3. **MARC parsing in two steps: `MARCXMLParser` gives raw records, then `DNBRecordMapper` maps them to `LookupRecord`.** The alternative, mapping inside the parser delegate, mixes XML events with bibliographic rules and is harder to test.
4. **No schema change. On Add Book after an applied lookup, the book gets `origin: .lookup` and `originNote` with the lookup id ("dnb:991442512", "openlibrary:/books/OL26424294M").** Both fields exist in SchemaV1 and in `LibrarySnapshot`, and `originNote` is not shown. The alternative, a `lookupID` attribute, needs SchemaV2 and a migration stage on the user's real library for a value nothing reads yet; the refresh feature can move it into an attribute later. Edit Book leaves origin and note unchanged.
5. **The merge is pure and derived.** `LookupMerge` produces a `LookupResult` that keeps the draft before Complete (`original`), the record's values as a full draft (`proposed`), the set of `filled` fields and the set of `offered` fields. Highlights, notes, `Use` and banner Undo are functions of `(result, current draft)`:
   - A field is highlighted while it is in `filled ∪ used` and its draft value equals the proposed value. Editing it removes the highlight, as the spec asks.
   - A note shows while the field is offered, not used, and its draft value differs.
   - Undo copies `original`'s values back for `filled ∪ used`.

   The alternative, flags set by `onChange` per field, needs one observer per field and drifts.
6. **Comparison for "same value":**
   - Text fields: `TextFolding.fold(AuthorName.normalize(_))`.
   - Year and pages: integers.
   - Languages: codes.
   - ISBN: `ISBN.parse(...).isbn13`.
   - Authors: the set of `AuthorName.matchKey`.

   This way "Ryu Murakami" equals "Ryū Murakami" and "liebeskind" equals "Liebeskind", and no note appears for case or diacritic differences.
7. **An empty title is filled. A non-empty title is only ever offered.** An ISBN-only search has no title, and the spec's rule "an empty field is filled" covers it.
8. **Cover:** the picked record's large cover is downloaded and normalized with `CoverImage.normalize` before the result is applied, so the sheet changes in one step and the offer appears only when an image exists.
   - The draft has no cover: the cover is filled.
   - The draft has a cover: "Use DNB cover" is offered.
   - Download or decode fails: nothing happens and no message shows.

   The alternative, downloading only when the user clicks Use, would show an offer for records that have no cover. DNB records carry no cover flag.
9. **The merge applies to the draft as it is when the result arrives, not as it was when Complete was clicked.** Values typed during the lookup count as the user's values and win.
10. **Matching (the user's rule):**
    - Title-and-author search: a record matches when its folded title starts with the folded typed title, and at least one typed author's match key equals the match key of one of the record's authors.
    - The title is compared twice, once with the non-sort part removed ("Buddenbrooks") and once with only the markers removed ("The Buddenbrooks"); either counts.
    - DNB authors are the 100 heading (any relator) and 700 headings with `$4 = aut`.
    - ISBN search: keep records whose ISBNs (ISBN-10s converted) contain the searched ISBN-13, then deduplicate by that ISBN, keeping the first. The OL Renoir fixture becomes one record.
11. **Order in "Choose an edition":** records in the draft's `language` at Complete time come first, then the rest. Each group is newest first; records without a year go last; the server order breaks ties. The first row is selected.
12. **Queries.**
    - DNB title-and-author: `tit=<word> and tit=<word> … and per=<surname> and mat=books`, `maximumRecords=100`.
      - `<surname>` is the part of the first author's sort name before the comma, or the last word of the name.
      - Words are split on whitespace, CQL-special characters (`" ( ) = < > / * \`) are removed, and empty words are dropped.
    - DNB ISBN: `num=<isbn13>`, `maximumRecords=10`.
    - The `query` value is percent-encoded with `=` and `+` escaped explicitly.
    - Open Library: `title`, `author` (the first author's name) and `limit=100`, or `isbn`, plus the research's `fields` list extended by `editions.format`.

    The alternative, a quoted CQL phrase for multi-word titles, was not probed; per-word `and` uses the verified combination form.
13. **"Showing the 100 newest…" appears when the service's total is above 100.** That is `numberOfRecords` for DNB and `numFound` for Open Library.
14. **Field extraction rules (DNB):**
    - Year: the first four-digit run in 1000–2999 of 264 ind2 1 `$c`, then 264 ind2 4, then 260 `$c`, then 008 positions 7–10.
    - Pages: the first Arabic integer in `300$a` whose next word is not a carrier or volume word (Bd, Bde, Band, Bände, vol, CD, DVD, Online-Ressource, Karte). It must be 1–99 999.
    - Language: `041$a`, else 008 positions 35–37, mapped through `BibliographicLanguage`.
    - Original language: `041$h` only, and only when it differs from the language.
    - Publisher: the first 264 ind2 1 `$b`, else `260$b`, trimmed.
    - ISBN: the first `020$a` that `ISBN.parse` accepts, preferring 13 digits. Display is `020$9` when it is the same number, else the digits. `024` ind1 3 is the fallback.

    The research's "leading integer" rule would turn "1 CD" and "2 Bände" into page counts.
15. **Author headings:** split at commas, drop empty parts and parts containing digits or parentheses, and keep the first two parts.
    - Display name is "<given> <surname>"; sort name is "<surname>, <given>".
    - Without a comma ("Man en", "John Williams"), the name stays as is and the sort name is `AuthorName.guessSortName`.
    - An author already in the library is reused with its stored sort name, through a new `Library.lookupAuthors(_:)`.
    - When the user typed authors, they stay, and a differing list is offered as one "Authors" offer.
16. **A language the popups do not offer leaves the field alone, with no offer.** A new `LanguageOptions.isOffered(_:locale:)` checks this.
17. **Sentences that name a source are separate catalog keys per source, chosen by a `switch`, never interpolated names.** German inflects ("aus der Deutschen Nationalbibliothek"), and the catalog rule is one literal key per call site. The source names themselves stay untranslated inside the values.
18. **The banner sentence with two counts uses one catalog key with plural `substitutions`** (`%1$lld`, `%2$lld`). `LocalizationCatalogTests` is extended to check substitution plurals. The alternative, two sentences joined with `Text + Text`, breaks the no-concatenation rule.
19. **The case "0 fields filled, some values differ" gets its own key per source:** "No empty fields to fill. %lld values differ from the Deutsche Nationalbibliothek and stay until you use them." / "Keine leeren Felder zu ergänzen. %lld Angaben weichen von der Deutschen Nationalbibliothek ab und bleiben, bis du sie übernimmst." (Open Library: "…differ from Open Library…" / "…weichen von Open Library ab…"). The spec's sentence would read "Filled in 0 empty fields".
20. **Thumbnails in "Choose an edition" load through `BookLookupService.coverData(for:size: .small)`, not `AsyncImage`.** All network access stays behind core protocols with one User-Agent and is fakeable. They load in a `.task(id: record.id)` per row and are cached in the picker's state for its lifetime.
21. **The sheet becomes 650 pt wide**, as in the design, so the header holds the title, `Vervollständigen` and `Stopp` side by side.
22. **Concurrency.** Services and the coordinator are `Sendable` structs. Their network and parse entry points are `@concurrent async` (the same form as `CoverImage.normalize`). Only value types (`LookupRecord`, `LookupResponse`) cross back to the main actor. Author resolution and the merge run on the main actor in the sheet's `LookupModel`. Nothing touches a `ModelContext` off the main actor, and no `@ModelActor` is needed because nothing is saved during a lookup.

## Components

All new core files sit in a new folder `Sources/BuchhalterCore/Lookup/`.

### `LookupQuery` (core, `LookupTypes.swift`)
Responsibility: what Complete searches for, built from the draft.
- `enum LookupQuery: Equatable, Sendable { case isbn(ISBN), titleAuthor(title: String, authors: [AuthorDraft]) }`
- `init?(draft: BookDraft, pendingAuthor: String)` (directional): a valid ISBN wins. Otherwise a non-empty title and at least one author, counting the uncommitted author text, give `.titleAuthor`. Otherwise nil, which disables Complete.
- `var isbnDisplay: String` gives the user's `isbnText` for the status line and hints.
- Must not: look at an invalid or incomplete ISBN.

### `LookupSource`, `LookupRecord`, `LookupAuthor`, `LookupResponse`, `LookupError` (core, `LookupTypes.swift`)
- `enum LookupSource: String, Sendable { case dnb, openLibrary }`.
- `struct LookupAuthor: Equatable, Sendable { name: String; sortName: String? }`. `sortName` is the cleaned inverted heading, nil when guessed.
- `struct LookupRecord: Identifiable, Equatable, Sendable`, with fields:
  - `id: String` ("dnb:<001>", "openlibrary:<edition key>") and `source`;
  - `title` (markers removed), `titleMatchKeys: [String]`, `subtitle: String?`, `authors: [LookupAuthor]`;
  - `year: Int?`, `pages: Int?`, `language: String?`, `originalLanguage: String?` (alpha-2);
  - `publisher: String?`, `isbn13s: [String]`, `isbnDisplay: String?`;
  - `cover: CoverReference?` (`enum { dnb(isbn13), openLibrary(coverID) }`).
- `struct LookupResponse: Sendable { records: [LookupRecord]; totalCount: Int }`. These are the records after the carrier filter and before match filtering.
- `enum LookupError: Error, Sendable { case unreachable(LookupSource) }`. It covers URL errors other than cancellation, HTTP status other than 200, unparseable bodies and SRU diagnostics.

### `HTTPClient` / `URLSessionHTTPClient` (core, `HTTPClient.swift`)
- `protocol HTTPClient: Sendable { func get(_ url: URL, timeout: TimeInterval) async throws -> (Data, Int) }` (directional).
- `URLSessionHTTPClient` uses an `.ephemeral` session (no cookies, no disk cache), sets `User-Agent: Buchhalter/0.1 (personal book app)` on every request, and rethrows cancellation unchanged.
- Must not: log URLs with user data, or retry on its own.

### `BookLookupService` (core, `BookLookupService.swift`)
- `protocol BookLookupService: Sendable { var source: LookupSource { get }; func search(_ query: LookupQuery) async throws -> LookupResponse; func coverData(for reference: CoverReference, size: CoverSize) async -> Data? }` (directional). `CoverSize` is `.small` or `.large`.
- `coverData` returns nil on any failure: 404, HTML content type, timeout (15 s), or bytes that do not start with a JPEG/PNG signature. Search requests time out after 20 s.

### `DNBService` (core, `DNBService.swift`)
Responsibility: builds SRU URLs (Decision 12), fetches, parses with `MARCXMLParser`, maps with `DNBRecordMapper`, drops non-print records, and returns `LookupResponse(totalCount: numberOfRecords)`.
- Key method: `static func url(for query: LookupQuery) -> URL`, testable on its own.
- Must not: filter matches (that is `LookupMatching`), or sort.

### `MARCXMLParser` (core, `MARCXMLParser.swift`)
Responsibility: an `XMLParser` delegate over the SRU response. It returns `numberOfRecords`, any SRU diagnostic, and `[MARCRecord]`. A record holds controlfields `[tag: String]` and an ordered `[DataField(tag, ind1, ind2, subfields: [(code, value)])]`.
- Namespaces are ignored: it matches local names (`record`, `controlfield`, `datafield`, `subfield`, `numberOfRecords`).
- Must not: interpret MARC semantics.

### `DNBRecordMapper` (core, `DNBRecordMapper.swift`)
- `static func record(from marc: MARCRecord) -> LookupRecord?`. It returns nil for non-print carriers (see Research) and for records without a 245 `$a`.
- It implements Decisions 14 and 15, strips U+0098/U+009C (keeping both title forms for matching) and trims ISBD punctuation.

### `OpenLibraryService` (core, `OpenLibraryService.swift`)
Responsibility: builds the `search.json` URL, decodes with `Codable`, and maps each work's first edition:
- title and subtitle from the edition, else the work;
- authors from `author_name`, inverted when it contains a comma;
- year: the first four-digit run of `publish_date[0]`;
- pages: `number_of_pages` when present;
- language: `language[0]` through `BibliographicLanguage`;
- publisher: `publisher[0]`;
- ISBNs: `isbn` validated by `ISBN.parse`;
- cover: the edition's `cover_i` (never the work's, which belongs to another edition).

It drops editions whose `format` contains "audio", "cd", "mp3", "ebook", "e-book" or "kindle" (case-folded). An edition without `format` is kept. `totalCount` is `numFound`.

### `BibliographicLanguage` (core, `BibliographicLanguage.swift`)
- `static func alpha2(_ code: String) -> String?` lowercases, maps the 20 B codes to T codes, then calls `Locale.LanguageCode(t).identifier(.alpha2)`.
- Must not: return three-letter codes. The draft stores two letters only.

### `LookupMatching` (core, `LookupMatching.swift`)
- `static func matches(_ records: [LookupRecord], for query: LookupQuery) -> [LookupRecord]` (Decision 10).
- `static func ordered(_ records: [LookupRecord], preferredLanguage: String?) -> [LookupRecord]` (Decision 11).
- `static func headingToName(_ heading: String) -> LookupAuthor` (Decision 15), shared by both mappers.

### `BookLookup` (core coordinator, `BookLookup.swift`)
Responsibility: runs the source sequence and returns what the sheet must do.
- `struct BookLookup: Sendable { primary: any BookLookupService; fallback: any BookLookupService; static let live: BookLookup }`.
- `@concurrent func run(_ query: LookupQuery, preferredLanguage: String?, onSource: @MainActor @Sendable (LookupSource) -> Void) async throws -> LookupOutcome` (directional).
- `enum LookupOutcome: Sendable { case single(LookupRecord), several(EditionList), none }`. `EditionList` carries the source, the ordered records, `totalCount` and `isTruncated` (`totalCount > 100`).
- `func cover(for record: LookupRecord) async -> Data?` fetches the large cover and runs `CoverImage.normalize`. It returns nil on failure.
- Sequence: primary search → match → if empty, `onSource(.openLibrary)` → fallback search → match. A thrown `LookupError` propagates and cancellation propagates.
- Must not: touch `Library`, `BookDraft` merging, or UI state.

### `LookupField`, `LookupResult`, `LookupMerge` (core, `LookupMerge.swift`)
- `enum LookupField: CaseIterable, Sendable { case title, subtitle, authors, year, pages, language, originalLanguage, publisher, isbn, cover }`.
- `struct LookupResult: Equatable, Sendable`, with:
  - `source`, `recordID`, `original: BookDraft`, `proposed: BookDraft`;
  - `filled: Set<LookupField>`, `offered: Set<LookupField>`, `used: Set<LookupField>`.
- `static func merge(_ record: LookupRecord, authors: [AuthorDraft], cover: Data?, into draft: BookDraft) -> (BookDraft, LookupResult)` (directional). Rules:
  - empty → fill; equal (Decision 6) → nothing; different → offer;
  - a title that is not empty → offer only;
  - an original language the record does not name → nothing;
  - a language that is not offered → nothing;
  - cover nil → nothing;
  - status, dates, rating, notes and collections are never read or written.
- Derived functions on `LookupResult`:
  - `isHighlighted(_:in:)`, `showsOffer(_:in:)`;
  - `use(_:on:) -> BookDraft` (copies one field from `proposed`, inserts into `used`);
  - `undo(on:) -> BookDraft`;
  - `offerValue(_:formatting:) -> String`: year "2009", pages "173", language name, authors as a locale list, ISBN display, text as is.
- Counts: `filledCount = filled.count` (the cover counts, matching the spec's German example with 4 filled and 2 differing); `differCount = offered.count`.

### `LookupMessages` (core, `LookupMessages.swift`)
Responsibility: every sentence the lookup shows, as `LocalizedStringResource` literals selected by `switch` over source and query kind (Decision 17). It covers:
- `searching(query, source)`;
- `noMatch(query)`;
- `unreachable(source)`;
- `banner(result)`: filled only, filled + differ, differ only, nothing;
- `editionsHeadline(list, query)`;
- `truncatedNote`;
- `offerLabel(source, value)` ("DNB: %@" / "Open Library: %@");
- `coverOffer(source)`.

Author lists format through `.formatted(.list(type: .and))` with the passed `Locale`. Tests check which key comes out for each state. In the test runner the values are the English keys.

### `Library.lookupAuthors(_:)` (core, `Store/LookupAuthorOperations.swift`)
- `@MainActor func lookupAuthors(_ authors: [LookupAuthor]) -> [AuthorDraft]`: an existing author by match key gives its stored name and sort name with `isExisting: true`. Otherwise the result is `AuthorDraft(name:, sortName: author.sortName ?? AuthorName.guessSortName(name))`. Duplicates by match key are dropped.
- Must not: insert anything. It reads `existingAuthors()` only.

### `LanguageOptions.isOffered(_:locale:)` (core, changed)
True for a two-letter code in `Locale.LanguageCode.isoLanguageCodes` with a localized name: the same set `codes(...)` offers.

### `BookFormatting` (core, changed)
Two directional additions for the edition rows:
- `editionByline(_ record: LookupRecord) -> String`: "Thomas Mann · Reclam · 2026" (the list of authors, then publisher, then year).
- `editionDetails(_ record: LookupRecord) -> String`: "781 pages · German · ISBN 978-3-15-011537-4". It reuses `pageCount`, `languageName` and the existing "ISBN %@" key.

### `LookupModel` (app, `Views/Sheets/Lookup/LookupModel.swift`, `@Observable`, main actor by default)
Responsibility: the lookup state of one editor sheet.
- State:
  - `phase`: `.idle`, `.running(LookupQuery, LookupSource)`, `.noMatch(LookupQuery)`, `.unreachable(LookupQuery, LookupSource)`;
  - `result: LookupResult?`, `editions: EditionList?` (drives the picker sheet);
  - `task: Task<Void, Never>?`, `generation: UUID`.
- Methods (directional):
  - `start(query:draft:library:apply:)`;
  - `choose(_ record:)`;
  - `stop()`;
  - `clearHint()`;
  - `use(_ field:, draft: inout BookDraft)`;
  - `undo(draft: inout BookDraft)`.
- `start` cancels any running task, clears hint, result and banner, and creates a new `generation`. Every await point checks that `generation` is still current before it touches state, so a stopped or replaced lookup never writes.
- Must not: write to the store or hold model objects.

### `LookupHeader` (app, `Views/Sheets/Lookup/LookupHeader.swift`)
Responsibility: the sheet title row and the strip under it. It holds:
- the title and the Complete button (magnifier icon, accent outline, `.help("Enter a title and author, or an ISBN")` while disabled); while running, "Looking up…" with a `ProgressView` and Stop;
- the grey explanatory line;
- the status line while running;
- the amber no-match hint;
- the red unreachable hint with Try Again;
- the green banner with Undo.

It takes the model and closures and has no AppKit.

### `EditionPickerSheet` (app, `Views/Sheets/Lookup/EditionPickerSheet.swift`)
Responsibility: "Choose an edition" / "Ausgabe wählen".
- Layout: the headline with the count, then the optional truncation line, then a `List(selection:)` of rows, then a footer with the hint text, Cancel (`.cancelAction`) and Use This Edition (`.defaultAction`, prominent).
- A row shows a 30×45 thumbnail (generated cover as fallback, via `GeneratedCoverView`), the title in `Theme.serif`, and the two formatted lines.
- `.contextMenu(forSelectionType: LookupRecord.ID.self, menu: { _ in }, primaryAction: use)` gives double-click.
- The first row is selected on appear.

### `LookupOfferNote` and `.lookupFilled(_:)` (app, `Views/Sheets/Lookup/LookupFieldDecorations.swift`)
- `LookupOfferNote(label:, action:)` is the 11 pt line "DNB: 2009 · Use" with a link-style button.
- `.lookupFilled(Bool)` is a modifier that draws the `#EEF6F3` fill and `#8FB8AD` 1 pt border on text fields and pickers.

### `BookEditorSheet` (app, changed)
- Owns `@State lookup = LookupModel()` and reads `@Environment(\.bookLookup)`.
- The header is replaced by `LookupHeader`.
- Each field row is wrapped in a `VStack` with its `LookupOfferNote`. Year and Pages each get their own `VStack` inside the existing `HStack`, as do Language and Original Language.
- The highlight comes from `lookup.result?.isHighlighted(field, in: draft)`.
- Two `onChange` hooks: one on `draft.title`, `draft.authors` and `draft.isbnText` calls `lookup.clearHint()`; the other presents `EditionPickerSheet` from `lookup.editions`.
- `save()` and Cancel call `lookup.stop()` first, and `.onDisappear` stops it too.
- On add, the origin is `.lookup` with `originNote: result.recordID` when `lookup.result` is non-nil and at least one field is still highlighted; otherwise `.manual`.
- Width is 650.

### `CoverPicker` (app, changed)
- New inputs: `highlighted: Bool` (the 2 pt `#8FB8AD` outline with 2 pt offset around the preview) and an optional `offer: (label: LocalizedStringResource, action: () -> Void)?`, which shows "Use DNB cover" next to the cover.

### `\.bookLookup` environment entry (app, `Views/Common/LibraryEnvironment.swift`, changed)
- `@Entry var bookLookup: BookLookup = .live`. It is the injection point for previews and the later barcode and assistant features.

### `Theme` (app, changed)
- Adds `filledFill #EEF6F3`, `filledBorder #8FB8AD`, `noteText #5F6670`, and the amber hint fill and text taken from `LookupStates.dc.html`.

## Interactions

**Enablement (main actor, every render).** `LookupQuery(draft:pendingAuthor:)` returns nil, so Complete is disabled with its tooltip. Typing never starts anything.

**Complete, one match.**
1. On click, the sheet builds the `LookupQuery` and calls `lookup.start(...)`, which creates `Task { … }` (main actor).
2. The task sets the phase to `.running(query, .dnb)`, so the status line appears. All fields stay bound to `draft` and editable.
3. It awaits `bookLookup.run(query, preferredLanguage: draft.language, onSource:)`. That runs `@concurrent` off the main actor: HTTP, XML parse, map, match. `onSource(.openLibrary)` hops to the main actor and changes the status line.
4. It returns `.single(record)` and checks `generation`.
5. It awaits `bookLookup.cover(for: record)`, which downloads off the main actor and runs `CoverImage.normalize` `@concurrent`. It checks `generation` again.
6. On the main actor:
   - `authors = library.lookupAuthors(record.authors)`;
   - `(newDraft, result) = LookupMerge.merge(record, authors:, cover:, into: draft)` against the current draft;
   - `draft = newDraft`, `lookup.result = result`, phase `.idle`.

   Highlights, notes and the banner render from `result` and `draft`. `DuplicateIndex.match(for: draft)` re-evaluates and may show "Already in your library: …".

**Complete, several matches.** `run` returns `.several(list)` and the model sets `editions = list`, which presents `EditionPickerSheet` over the editor.
- Use This Edition, Return or double-click calls `lookup.choose(record)`, then dismisses the picker. `choose` continues with steps 5–6 inside a new task with the same generation.
- Cancel or Esc sets `editions = nil` and phase `.idle`. Nothing changes.

**No match.** `run` returns `.none`, which sets phase `.noMatch(query)`, so the amber hint shows. The draft is untouched.

**Unreachable.** `run` throws `LookupError.unreachable(source)`, which sets phase `.unreachable(query, source)`, so the red hint shows. Try Again calls `start` with a query rebuilt from the current draft.

**Stop / Cancel / Save during a lookup.** `lookup.stop()` cancels the task and replaces `generation`, so any late result is dropped. The phase returns to `.idle`. Save proceeds with the current `draft` exactly as today.

**Hints clear.** `onChange` of title, authors or ISBN calls `clearHint()`, which affects no-match and unreachable only; the banner and notes stay.

**Use.** `lookup.use(field, draft: &draft)` copies the field from `result.proposed` and inserts it into `used`. The note disappears because the values are now equal, and the field is highlighted. The authors offer replaces the whole list. The cover offer replaces `coverData`.

**Banner Undo.** `lookup.undo(draft: &draft)` restores `original` for `filled ∪ used`, then sets `result = nil`, which removes the banner, notes and highlights.

**Complete again.** `start` resets `result`. The new merge runs against the current draft, so values filled by the first lookup now count as the user's values.

**Saving.**
- Add: `library.addBook(draft, origin:, originNote:)` in one `change("Add Book")`.
- Edit: `updateBook` unchanged.

Either way it is one undo step. The downloaded cover lives only in `draft.coverData` until then; Cancel discards it with the sheet's state.

## Changes by file

| File | New/changed | Change |
|---|---|---|
| `Sources/BuchhalterCore/Lookup/LookupTypes.swift` | new | `LookupQuery`, `LookupSource`, `LookupRecord`, `LookupAuthor`, `CoverReference`, `CoverSize`, `LookupResponse`, `LookupError` |
| `Sources/BuchhalterCore/Lookup/HTTPClient.swift` | new | `HTTPClient` protocol and `URLSessionHTTPClient` (ephemeral, User-Agent, timeouts) |
| `Sources/BuchhalterCore/Lookup/BookLookupService.swift` | new | Service protocol |
| `Sources/BuchhalterCore/Lookup/DNBService.swift` | new | SRU URL building, fetch, carrier filter, total |
| `Sources/BuchhalterCore/Lookup/MARCXMLParser.swift` | new | `XMLParser` delegate to raw MARC records, `numberOfRecords`, diagnostics |
| `Sources/BuchhalterCore/Lookup/DNBRecordMapper.swift` | new | MARC to `LookupRecord`: title markers, punctuation, year, pages, languages, publisher, ISBN, authors |
| `Sources/BuchhalterCore/Lookup/OpenLibraryService.swift` | new | `search.json` URL, Codable decode, format filter, mapping, cover URLs |
| `Sources/BuchhalterCore/Lookup/BibliographicLanguage.swift` | new | ISO 639-2/B table and alpha-2 conversion |
| `Sources/BuchhalterCore/Lookup/LookupMatching.swift` | new | Real-match filter, ISBN filter and dedupe, edition order, heading-to-name |
| `Sources/BuchhalterCore/Lookup/BookLookup.swift` | new | Coordinator: DNB, then Open Library on zero matches; outcome; cover fetch and normalize |
| `Sources/BuchhalterCore/Lookup/LookupMerge.swift` | new | `LookupField`, `LookupResult`, merge, use, undo, highlight and offer predicates, counts |
| `Sources/BuchhalterCore/Lookup/LookupMessages.swift` | new | All lookup sentences as catalog literals per source and query kind |
| `Sources/BuchhalterCore/Store/LookupAuthorOperations.swift` | new | `Library.lookupAuthors(_:)` |
| `Sources/BuchhalterCore/Logic/LanguageOptions.swift` | changed | `isOffered(_:locale:)` |
| `Sources/BuchhalterCore/Logic/BookFormatting.swift` | changed | `editionByline`, `editionDetails` |
| `Sources/Buchhalter/Views/Sheets/Lookup/LookupModel.swift` | new | Per-sheet lookup state, task, generation guard |
| `Sources/Buchhalter/Views/Sheets/Lookup/LookupHeader.swift` | new | Title, Complete/Stop, explanatory line, status line, hints, banner |
| `Sources/Buchhalter/Views/Sheets/Lookup/EditionPickerSheet.swift` | new | "Choose an edition" list with thumbnails, keyboard, double-click |
| `Sources/Buchhalter/Views/Sheets/Lookup/LookupFieldDecorations.swift` | new | `LookupOfferNote`, `.lookupFilled(_:)` |
| `Sources/Buchhalter/Views/Sheets/BookEditorSheet.swift` | changed | Header, notes, highlights, picker presentation, stop on save/cancel/disappear, origin on add, width 650 |
| `Sources/Buchhalter/Views/Sheets/CoverPicker.swift` | changed | `highlighted` outline, optional cover offer |
| `Sources/Buchhalter/Views/Common/LibraryEnvironment.swift` | changed | `\.bookLookup` entry, default `.live` |
| `Sources/Buchhalter/Views/Common/Theme.swift` | changed | Filled, note and amber hint colours |
| `Package.swift` | changed | `BuchhalterCoreTests`: `exclude: ["Fixtures"]` (fixtures read through `#filePath`, no package resources) |
| `Tests/BuchhalterCoreTests/Fixtures/*` | new (moved) | The six files from `specs/planned/book-lookup/fixtures/`, moved, not copied |
| `Tests/BuchhalterCoreTests/LookupTestSupport.swift` | new | `fixture(_:)` loader via `#filePath`; `FakeHTTPClient` (URL → fixture/status/error, records requested URLs); `FakeLookupService` |
| `Tests/BuchhalterCoreTests/MARCParsingTests.swift` | new | Parser and DNB mapper against the fixtures |
| `Tests/BuchhalterCoreTests/OpenLibraryTests.swift` | new | Open Library URL and mapping against the fixtures |
| `Tests/BuchhalterCoreTests/BibliographicLanguageTests.swift` | new | B/T table and alpha-2 |
| `Tests/BuchhalterCoreTests/LookupMatchingTests.swift` | new | Filter, ISBN dedupe, order |
| `Tests/BuchhalterCoreTests/BookLookupTests.swift` | new | Coordinator outcomes, fallback, failures, cancellation |
| `Tests/BuchhalterCoreTests/LookupMergeTests.swift` | new | Fill, offer, use, undo, highlight, counts; Piercing example |
| `Tests/BuchhalterCoreTests/LookupMessagesTests.swift` | new | Correct key per state and source |
| `Tests/BuchhalterCoreTests/BookOperationsTests.swift` | changed | `lookupAuthors`; add with origin `.lookup` and note survives undo/redo |
| `Tests/BuchhalterCoreTests/LocalizationCatalogTests.swift` | changed | Substitution plurals checked; German lookup terms pinned |
| `Resources/Localizable.xcstrings` | changed | New keys via `make strings`, German values added, plural and substitution variants |
| `docs/dev/architecture.md` | changed | Targets/Layout (`Lookup/`), Data flow (lookup concurrency), UI structure (header, picker), Roadmap Book lookup now describes the code (DNB + Open Library; lookup id in `originNote` until a schema change), Decisions (new entry), Open points (remove "Open Library or Google Books") |

## Testing

**Unit tests** (Swift Testing). Every one runs offline against fixtures or fakes.

- **`MARCParsingTests`**:
  - `dnb-buddenbrooks-mann.xml`: `numberOfRecords == 477`; 20 records parsed; 19 after the carrier filter (the Polish CD "Buddenbrookowie" is dropped through `337$a`/`300$a` although its `007` is "tu").
  - `&#152;The&#156; Buddenbrooks`: title "The Buddenbrooks", match keys contain "buddenbrooks".
  - Year forms: "[2026]" → 2026, "©2026" → 2026, "copyright 2026" → 2026, "2025.05" → 2025.
  - Pages: "666 pages" → 666, "717 mian" → 717.
  - Headings: "Mann, Thomas,, 1875-1955" → "Thomas Mann" / "Mann, Thomas".
  - Languages: Georgian "geo" → "ka", Chinese "chi" → "zh", Russian with original "ger" → "ru"/"de".
  - `dnb-isbn-piercing.xml`: title "Piercing", subtitle "Roman", author "Ryū Murakami" sorted "Murakami, Ryū", publisher "Liebeskind", year 2009, pages 173, language "de", original "ja", ISBN 9783935890595 shown as "978-3-935890-59-5".
  - `dnb-stoner-williams.xml`: "380 Seiten, 5 ungezählte Seiten" → 380; `&#152;Der&#156; Mann, der …` stripped.
  - `dnb-no-match.xml`: 0 records, total 0.
  - Pages parse: "1 CD (…)" and "2 Bände" give nil.
- **`DNBService` URLs** (in `BookLookupTests` via `FakeHTTPClient`): the title-and-author query for "Buddenbrooks" by "Thomas Mann" contains `tit=Buddenbrooks and per=Mann and mat=books` and `maximumRecords=100`, with `=` escaped. The ISBN query uses `num=9783935890595`. The User-Agent header is set. CQL special characters are stripped from titles.
- **`OpenLibraryTests`**:
  - `openlibrary-stoner-williams.json`: 4 records after the format filter (the Blackstone Audio edition is dropped only if its `format` says audio; the captured fixture has no `format` field, so the test asserts 5 records and a separate inline JSON with `"format":"audio cd"` asserts the drop).
  - Mapping: "Sep 23, 2014" → 2014, "eng" → "en", edition `cover_i` used and work `cover_i` ignored.
  - `openlibrary-isbn-stoner.json` with ISBN 9780940322776: one record after dedupe.
  - "Renoir, Jean" → "Jean Renoir".
- **`BibliographicLanguageTests`**: all 20 B codes map to their alpha-2; "jpn" → "ja"; "xxx" → nil.
- **`LookupMatchingTests`**:
  - The Buddenbrooks fixture filtered for "Buddenbrooks" by "Thomas Mann" keeps the German "Buddenbrooks…" editions and drops "Huch, alle tot?…", "Meine Buddenbrooks", "Thomas Mann: Buddenbrooks", "Huset Buddenbrook" and "Bu deng bu luo ke jia zu".
  - "Ryu Murakami" typed matches "Murakami, Ryū".
  - Order with preferred "de": German first, newest first, nil years last.
  - An ISBN query ignores title and author.
- **`BookLookupTests`** (with `FakeLookupService`):
  - one match → `.single`; several → `.several` with `isTruncated` when total > 100; zero on DNB → Open Library asked and `onSource(.openLibrary)` called;
  - zero on both → `.none`;
  - DNB unreachable → throws `.unreachable(.dnb)` and Open Library is never asked;
  - Open Library unreachable → `.unreachable(.openLibrary)`;
  - a cancelled task → `CancellationError` and no outcome;
  - cover: 404 → nil; HTML body → nil; JPEG → normalized JPEG at most 1200 px (a generated test image, as in `CoverTests`).
- **`LookupMergeTests`**:
  - Empty draft + Piercing record: 9 fields filled (title included, cover included when given), 0 offered.
  - The spec's Edit Book example (year 1994, pages 176, typed author "Ryu Murakami", own title "Piercing"): filled = subtitle, publisher, originalLanguage, cover; offered = year (2009) and pages (173); counts 4/2.
  - Rules: the title is never replaced; an unoffered language is ignored; status, dates, rating, notes and collections are byte-for-byte unchanged.
  - Display: `use(.year)` sets "2009" and hides the note; editing a filled field removes its highlight.
  - `undo` restores every filled and used field, including a cover the user did not have.
  - Draft has a cover: the cover is offered, not filled.
- **`LookupMessagesTests`**: the right key for each phase and source, the singular/plural selection inputs, and the "differ only" case.
- **`BookOperationsTests`**:
  - `lookupAuthors` reuses an existing "Thomas Mann" with a custom sort name, and gives a new author the heading sort name.
  - `addBook(draft, origin: .lookup, originNote: "dnb:991442512")` stores both, and undo/redo restores them (through `LibrarySnapshot`, already covered for these fields).
- **`LocalizationCatalogTests`**:
  - Every `substitutions.*.variations.plural` has `one` and `other` in both languages.
  - German terms pinned: Complete → Vervollständigen, "Looking up…" → "Wird gesucht…", Stop → Stopp, "Choose an edition" → "Ausgabe wählen", "Use This Edition" → "Diese Ausgabe übernehmen", Use → Übernehmen, "Use DNB cover" → "DNB-Cover übernehmen", Undo → Widerrufen, "Try Again" → "Erneut versuchen".

**Commands** (the implementer runs these; all are allowed):
1. `make strings`, then add the German values and the plural and substitution variants in `Resources/Localizable.xcstrings`.
2. `swift test`: all tests pass, including the catalog test.
3. `make app` builds `build/Buchhalter.app`.

No agent starts the app.

**Manual checks** are for the user, on the real library with the network on unless noted. Start with `open build/Buchhalter.app`, and for German `open build/Buchhalter.app --args -AppleLanguages '(de)'`.
1. Add Book shows Complete at the top right and the grey line. With an empty title, or a title and no author, Complete is disabled and its tooltip reads "Enter a title and author, or an ISBN". Typing starts nothing.
2. "Buddenbrooks" + "Thomas Mann" → Complete. "Choose an edition" opens with the German editions newest first, the top row selected, and no CD or study guides. The arrow keys move the selection. Double-click fills the sheet. Repeat and use Cancel, then Esc: nothing changes.
3. ISBN 978-3-935890-59-5 alone → the sheet fills at once. The filled fields are green and the cover has a green outline. The banner reads "Filled in … fields from the Deutsche Nationalbibliothek…".
4. Banner Undo → every filled field is back to empty, and the highlights, notes and banner are gone.
5. Edit an existing "Piercing" with year 1994 and pages 176 (or any book with a differing year) → the notes "DNB: 2009 · Use" and "DNB: 173 · Use" appear. Use takes the value. The title stays. A book with its own cover keeps it and shows "Use DNB cover".
6. Status, dates, rating, notes and collections are unchanged after Complete.
7. A book only in Open Library (e.g. an English title DNB lacks) → the status line names Open Library and the banner says "from Open Library".
8. During a lookup, type in the fields and click Stop: nothing changes. Start a lookup and click Add Book: the book is added with the typed values.
9. "Buddenbroks" + "Thomas Mann" → the amber no-match hint. Change the title: the hint goes away.
10. With Wi-Fi off, Complete → the red hint with Try Again. Add the book by hand: it works.
11. Add a book with a looked-up cover, quit, turn the network off, relaunch: the cover shows.
12. A filled-in ISBN of a book already in the library → "Already in your library: …".
13. After saving, ⌘Z reverts the whole add or edit in one step.
14. The same flows in German: the button, line, status line, banner (plural "1 Feld"), hints, notes and the edition sheet are all in German, and "Vervollständigen" fits the header.

## Permissions

| Action | Status |
|---|---|
| Edit and create files in the repo | Allowed (normal implementer work) |
| `swift build`, `swift test`, `make app`, `make strings`, `xcrun xcstringstool` | Allowed in `.claude/settings.json` |
| Move the six fixtures from `specs/planned/book-lookup/fixtures/` to `Tests/BuchhalterCoreTests/Fixtures/` (`mv`; the folder is untracked, so not `git mv`) | Not in the allowlist. Asks once. The source folder ends up empty, which is intended. This is a move inside the repo; nothing is deleted |
| Outgoing HTTPS from the app to `services.dnb.de`, `portal.dnb.de`, `openlibrary.org`, `covers.openlibrary.org` | Works today (no sandbox). Phase 2 needs the entitlement `com.apple.security.network.client` |
| Network access from tests | None. Tests use fixtures and fakes only |
| Starting the app | Not done by agents; the user starts it |
| Schema or store change | None. No `VersionedSchema` change, no migration; the user's library file is untouched |
| curl, WebFetch | Not needed by the implementer; fixtures exist |

No destructive or irreversible change is part of this plan.

## Risks and open points

- **DNB default order is not documented.** The fixture shows newest first. The "Showing the 100 newest" line relies on that. If DNB changes its order, the 100 records kept may not be the newest. The app's own sort still orders what it got.
- **Multi-word titles as `tit=word and tit=word`** follow the verified `and` form, but word order and stop words ("Der", "Die") are not probed. A title of only stop words may return too much; the client filter keeps that correct.
- **`num=<isbn13>`** may miss records catalogued with an ISBN-10 only (books from before 2007). The implementer does not add a second query; a miss shows the no-match hint, which suggests title and author.
- **The MVB cover service** (`portal.dnb.de/opac/mvb/cover`) is undocumented and can change or vanish. Every failure is "no cover", so the flow keeps working.
- **Open Library:** `editions.format` is often missing, so an audio edition without `format` can slip through. Page counts are usually absent. Both affect only the fallback.
- **The `substitutions` entry** for the two-count banner is written by hand in the catalog JSON after `make strings` (the sync writes a plain key with `%1$lld`/`%2$lld`). The extended catalog test catches a broken entry.
- **Wording points for the user:**
  - The spec's "Check them, then add the book." is used in Edit Book too.
  - The new "differ only" sentence (Decision 19) is not in the spec.
- **Design files:** the five Book Lookup boards are saved locally: `LookupAdd`, `LookupMatches` and `LookupFilled` as `Main.dc.html`, `Matches.dc.html` and `Filled.dc.html` in `/private/tmp/claude-501/-Users-juergen-dev-buchhalter/d692322d-fb9c-4412-95ce-c21f9501b8d1/scratchpad/lookup-design/project/`, and `LookupStates.dc.html` and `LookupEditGerman.dc.html` in `/private/tmp/claude-501/-Users-juergen-dev-buchhalter/d692322d-fb9c-4412-95ce-c21f9501b8d1/scratchpad/artifact-files/95eb6174-660c-42ff-aea6-175695b400bc/project/`. If the scratchpad is gone, read them from the canvas link with the Artifact read action.
- **Fixture name:** `openlibrary-isbn-stoner.json` holds Jean Renoir records (ISBN 9780940322776). Tests name it by content; renaming it during the move to `openlibrary-isbn-renoir.json` is the implementer's choice and keeps the tests clear.
- **Sheet over sheet on macOS 27:** `EditionPickerSheet` is presented from inside `BookEditorSheet`. If focus or `.defaultAction` misbehave in the nested sheet, the implementer reads Apple's macOS 27 SwiftUI release notes before changing the approach.
- **Left to the implementer:** exact paddings, font sizes and colours from the design; the amber hint colours (read from `LookupStates.dc.html`); thumbnail size in the picker rows; the accessibility labels for Complete, Stop, Use and Undo (all through the catalog, both languages).
- **`architecture.md` must be updated in the same change** (see Changes by file). The spec moves to `specs/done/` only through `/dev:archive`.