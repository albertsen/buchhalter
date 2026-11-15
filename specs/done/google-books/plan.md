# Google Books — Plan

## Current State (audited 2026-11-15)

**Toolchain and package.** Xcode 27.2, Swift 6.4.2, macOS 27 SDK. `Package.swift` uses swift-tools-version 6.2 and has three targets:
- `BuchhalterCore`: library, Swift 6 mode.
- `Buchhalter`: executable, `defaultIsolation(MainActor.self)`.
- `BuchhalterCoreTests`: excludes `Fixtures`, which are read through `#filePath`.

There are no third-party dependencies and no `Package.resolved`. Baseline: `swift test` passes 220 tests in 33 suites.

**App shell.**
- `Sources/Buchhalter/App/BuchhalterApp.swift` has one scene, `Window("Buchhalter", id: "main")` with `RootView`, `.modelContainer(container)` and `.commands { LibraryCommands(); BookCommands() }`. There is no `Settings` scene, so ⌘, does nothing today. `AppDelegate` is attached with `@NSApplicationDelegateAdaptor`.
- `Resources/Info.plist`: `CFBundleIdentifier` `local.buchhalter`, `LSMinimumSystemVersion` 27.0.
- `make app` copies the binary, `Info.plist`, `AppIcon.icns` and the compiled catalog. It then runs `codesign --force --sign -` (ad-hoc) and `lsregister -f`. There is no entitlements file and no sandbox. The Makefile copies named resources only, so a new bundled file needs its own `cp` line.

**Per-Mac preferences.**
- `LibraryListOrder` (`Sources/BuchhalterCore/Logic/LibraryListOrder.swift`) is a pure `Sendable` value type. It parses a raw string (`"reading,wantToRead,read,all"`), drops unknown and repeated entries, appends missing ones, and has `move(fromOffsets:toOffset:)` with the same contract as `onMove`.
- `SidebarView` stores it with `@AppStorage("libraryListOrder")` and reorders with `ForEach.onMove`.
- `RootView` uses `@AppStorage` for `selectedList`, `selectedBook` and `openBook`.
- This is the pattern for the source order and switches.

**No Keychain code and no settings UI exist** (no `SecItem` anywhere).

**Lookup in `BuchhalterCore/Lookup/`.**
- `LookupSource` is `enum { dnb, openLibrary }` with String raw values. `LookupError` has one case, `.unreachable(LookupSource)`.
- `BookLookupService` protocol:
  - `source`
  - `search(_:) async throws -> LookupResponse`, which throws `.unreachable` for every failure except cancellation
  - `coverData(for:size:) async -> Data?`
- `CoverDownload.fetch` requires HTTP 200 and a JPEG or PNG signature (`isImage`).
- `BookLookup` (struct, `Sendable`):
  - Has fixed `primary` and `fallback` services. `static let live = BookLookup(primary: DNBService(), fallback: OpenLibraryService())`.
  - `run(_:preferredLanguage:onSource:)` throws at once when a source fails. There is no fallback on failure (architecture Decision 15).
  - `findCover(_:preferredLanguage:)` loops queries on the outside and sources on the inside, and falls through on failure. It throws the first failure only when no source was reached.
  - `cover(for:)` and `thumbnail(for:)` choose the service with `record.source == primary.source ? primary : fallback`.
- `EditionList.isTruncated` uses `DNBService.maximumRecords` (100) for every source.
- `LookupRecord` has `cover` and `workCover: CoverReference?`. `CoverReference` is `.dnb(isbn13:)` or `.openLibrary(coverID:)`.
- `LookupMessages` has one literal catalog key per source, chosen in exhaustive `switch`es: `searching`, `unreachable`, `banner` (4 variants), `offerLabel`, `coverOffer`. Adding a case to `LookupSource` breaks the compile until every switch has a Google Books branch. That is intended.
- `LookupMatching.matches` keeps, for an ISBN search, the first record that carries the ISBN; for title and author, records where a title form starts with the typed title and an author matches. `ordered` puts the preferred language first, then newest first.
- `DNBService.words(in:)` and `surname(of:)` are internal statics and can be reused.

**HTTP.**
- `HTTPClient.get(_:timeout:)` takes no headers.
- `URLSessionHTTPClient` uses an ephemeral session with User-Agent `Buchhalter/0.1 (personal book app)`.
- `Error.isCancellation` exists.

**Lookup on the app side.**
- `\.bookLookup` (`@Entry`, default `.live`) is in `Views/Common/LibraryEnvironment.swift`.
- `LookupModel`: `phase` has `.idle`, `.running(LookupQuery, LookupSource)` (it starts with `.dnb` hardcoded), `.noMatch` and `.unreachable(LookupQuery, LookupSource)`. It checks a `generation` after every await.
- `LookupHeader`: Complete is disabled by `canComplete`, with the tooltip "Enter a title and author, or an ISBN". The grey line is the literal "Type a title and author, or an ISBN. Complete looks up the rest in the Deutsche Nationalbibliothek, including the cover."
- `EditionPickerSheet` is 560 pt wide and loads thumbnails through `bookLookup.thumbnail(for:)`.
- `BookDetailView.findCover()` writes `model.errorMessage`, which shows in RootView's generic "Something went wrong" alert. The messages are "No cover found for this book." and "Can't reach the Deutsche Nationalbibliothek or Open Library. Check the internet connection." The Find Cover button and its context-menu item are disabled only by `canFind`.

**Tests and localization.**
- `LookupTestSupport.swift` has `fixture(_:)`, `FakeHTTPClient` (actor, records URLs), `FakeLookupService` and `makeRecord` (its id prefix is `dnb` or else `openlibrary`).
- Fixtures: 4 DNB XML and 2 Open Library JSON files.
- `LocalizationCatalogTests` requires an explicit, translated English and German unit for every key, and checks the spec's German terms.
- `make strings` syncs new keys without German.

**Notes for the implementer.**
- The spec changes the failure rule: a source that cannot be reached is skipped in Complete too. Architecture Decision 15 and the Book lookup section ("A failure of the first does not fall back") are replaced in this change.
- AGENTS.md says "no App Store, no distribution". The spec says the app will go to the Mac App Store. Only the opening sentence and the Quick facts change here. Sandboxing and signing are out of scope.
- The spec was amended: an edition list from Google Books shows the "powered by Google" logo, and each row has a `Google Books` link to the book's page.
- The help sheet's intro sentence is only paraphrased in the spec ("says the key is free and that a Google account is needed"). This plan fixes the wording (see Components, GoogleBooksKeyHelpSheet).
- No SwiftData schema change. The library store is not touched.

## Research

All findings are valid for the locally installed versions: Xcode 27.2, Swift 6.4.2, macOS 27 SDK. They were checked against Google's online API as of 2026-11-15.

**Google Books API v1.** Sources: developers.google.com/books/docs/v1/using, …/reference/volumes/list, …/reference/volumes.
- Search: `GET https://www.googleapis.com/books/v1/volumes?q=…`. The keywords `isbn:`, `intitle:` and `inauthor:` are joined with `+` and ANDed.
- Parameters used here: `printType=books`, `maxResults` (0–40), `projection`. The `fields` partial-response parameter is a Google-wide system parameter and is not documented on the Books pages, so the first fixture recording verifies it.
- `volumeInfo` fields:
  - `title`, `subtitle`, `authors[]`, `publisher`
  - `publishedDate` ("2005-11-15" or "1890")
  - `pageCount`, `language` (ISO 639-1)
  - `industryIdentifiers[]` (`ISBN_10`, `ISBN_13`, `ISSN`, `OTHER`)
  - `imageLinks` (`smallThumbnail`, `thumbnail`, and on a single-volume GET possibly `small`, `medium`, `large`, `extraLarge`)
  - `printType` (`BOOK`/`MAGAZINE`), `infoLink`, `canonicalVolumeLink`
- `saleInfo.isEbook`.
- An empty result is `{"kind":"books#volumes","totalItems":0}` with no `items`.
- Errors come as JSON `{"error":{"code","message","errors":[{reason}],…}}`.

**Keys.**
- A keyless request on 2026-11-15 returned HTTP 429 "Quota exceeded … 'Queries per day'". Keyless use is not possible.
- Google Cloud API keys can be sent in the `X-goog-api-key` request header instead of `key=` (cloud.google.com/docs/authentication/api-keys-use). This plan uses the header, so the key never appears in a URL, a `URLError` description or a fixture. The first fixture recording confirms that the Books API accepts it.
- The status codes for an invalid key, a disabled API and a used-up quota are not documented on the Books pages. Common Google practice:
  - 400 with reason `keyInvalid` or "API key not valid"
  - 403 with `accessNotConfigured`/`SERVICE_DISABLED` or `dailyLimitExceeded`
  - 429 for quota

  The recorded fixtures confirm or correct this rule.

**Branding.** Source: developers.google.com/books/branding.
- "The 'powered by Google' graphic must always be displayed alongside any search modules or results." The graphic is at `https://books.google.com/googlebooks/images/poweredby.png`.
- "Every book result displayed in your application must have a prominent link to … the Google Books page for that book."
- Results must not be reordered or altered. This conflicts with the spec's "newest first" and the match filter (see Risks).

**Covers.**
- Image URLs come back as `http://books.google.com/books/content?id=…&printsec=frontcover&img=1&zoom=1&edge=curl&source=gbs_api`.
- They must be upgraded to `https` for App Transport Security, and `edge=curl` (the page-curl effect) is removed.
- `zoom` selects the size.
- A volume without a cover has no `imageLinks`. Requesting its content URL returns Google's "image not available" picture, which is recorded once as a fixture.

**Keychain.** Applies to an unsandboxed, ad-hoc-signed app on macOS 27.
- `SecItemAdd`/`SecItemCopyMatching`/`SecItemUpdate`/`SecItemDelete` with `kSecClassGenericPassword` and without `kSecUseDataProtectionKeychain` use the file-based login keychain. No entitlement is needed.
- The item's access control trusts the creating app's code signature. Each ad-hoc build has a new signature, so macOS asks "Buchhalter wants to use your confidential information" once per build when the app reads the secret. The user accepted this until proper signing exists.
- A query for attributes only (`kSecReturnAttributes`, no `kSecReturnData`) does not touch the secret and does not prompt.
- An item added with `security add-generic-password` is owned by `security`, and the app's first read prompts the same way.
- The data protection keychain needs a `keychain-access-groups` entitlement and a provisioning profile, which are not available today.

**SwiftUI.**
- The `Settings { }` scene gives the standard settings window, the app-menu item "Settings…" (localized by macOS as "Einstellungen…") and ⌘,. ⌘, brings an open window to the front.
- `TabView { Tab("…", systemImage:) { … } }` inside `Settings` gives the toolbar tabs, and the window title follows the selected tab.
- `@Environment(\.openSettings)` (`OpenSettingsAction`, macOS 14+) opens the window from a view.
- `ForEach.onMove` reorders rows, as `SidebarView` already does.

## Decisions

1. **Google Books is a third `BookLookupService`, `GoogleBooksService`, in `BuchhalterCore`.** Complete, Find Cover, the edition picker and the messages treat it like the other two. Alternative: a cover-only add-on for Find Cover. Rejected because the spec makes it a full source for Complete.

2. **`BookLookup` holds an ordered list of active services instead of `primary` and `fallback`.** `run` asks them in order and skips a source that fails. It throws only when no source answered. Alternative: keep two slots and chain a third. Rejected because the order is user-defined and of any length.

3. **One persisted value type, `LookupSourceList`, holds order and switches.** It is stored in UserDefaults under `lookupSources` as `"dnb:on,openLibrary:on,googleBooks:off"`. It follows `LibraryListOrder`: parsing drops unknown and repeated entries and appends missing sources with their default switch. Alternative: an order key plus a set of disabled sources. Rejected because one string with one parser and one test suite is enough. The value is per Mac and does not sync (spec Non-goals).

4. **Which sources are active is derived.** A source is active when its switch is on. Google Books is active only if it is also on with a saved key. A missing key never flips the stored switch, except that Remove sets Google Books off explicitly, as the spec says.

5. **The key is stored as a Keychain generic password with service `Buchhalter Google Books` and account `api-key`.** These names do not contain the bundle id, so the item survives the later change from `local.buchhalter` to a reverse-DNS id. `kSecAttrComment` holds the key's last four characters, so the masked key shows without reading the secret and without a prompt. An item created with `security add-generic-password` has no comment, so the pane then reads the secret once. Alternative: last four characters in UserDefaults. Rejected because AGENTS.md keeps everything about keys in the Keychain.

6. **Keychain code lives in the app target (`App/KeychainSecretStore.swift`), behind a `SecretStore` protocol in `BuchhalterCore`.** AGENTS.md limits the core to Foundation and SwiftData, and the Keychain cannot be unit-tested without touching the user's real login keychain. Security.framework exists on iOS, so the file is shared-ready and not in `Mac/`. Core tests use `FakeSecretStore`.

7. **The key is read lazily, off the main actor, only when Google Books is actually asked.** `GoogleBooksService` gets the `SecretStore`, not the key string. The once-per-build prompt therefore appears only when a lookup reaches Google Books, or when the pane needs the secret. `KeychainSecretStore` is an actor that caches the value after the first read. If the read fails or the user denies it, Google Books is unreachable for that lookup, and the next source is asked.

8. **The key goes in the `X-goog-api-key` header, never in the URL.** `HTTPClient.get` gains a `headers` parameter. A protocol extension keeps `get(_:timeout:)` for the other callers. Alternative: `key=` in the query. Rejected because the key would show up in `URLError` descriptions, fixtures and anything that prints a URL. If the recorded answers show that the header does not work for the Books API, the implementer switches to `key=` and must strip it from every fixture. This is the only fallback.

9. **`LookupError` gains `.keyRejected(LookupSource)` and `.noSourceReached([LookupSource])`.** Services throw `.unreachable` or `.keyRejected`. `BookLookup` throws `.noSourceReached(sourcesAsked)` when every active source failed. The unreachable hint names the one source when exactly one was asked, and says "any book source" otherwise.

10. **A rejected key is classified by status and body.**
    - 401, 403 and 429 mean `.keyRejected`.
    - 400 means `.keyRejected` only when the error names the key: reason `keyInvalid`, details reason `API_KEY_INVALID`, or a message containing "API key not valid".
    - Any other status, a transport error or an unreadable body means `.unreachable`.

    This keeps a malformed-query 400 from falsely turning the Settings line red. The recorded fixtures confirm the codes.

11. **`BookLookup` reports what happened to each source through an observer.** `BookLookup.observer` is an optional `@MainActor @Sendable (LookupEvent) -> Void`, with events `.asking(source)`, `.answered(source)` and `.failed(source, LookupError)`. The app sets it to `BookSources.record`, so every caller (Complete, Find Cover, later the assistant) updates the Google Books key state without knowing about it. `run` and `findCover` also take a per-call `onEvent` for the status line, which replaces `onSource`. Alternative: return a report from each call. Rejected because every caller would have to forward it.

12. **The key state is persisted, the transient line is not.** `GoogleBooksKeyState` is stored in UserDefaults as `googleBooksKeyState` (`works`, `unchecked`, `rejected`). It is not a secret. The pane derives its line from that state, the switch, and a pane-local "just saved" flag. The transitions are pure functions in the core and are tested:
    - Save → `works`
    - Save Anyway → `unchecked`
    - `.answered(.googleBooks)` → `works`
    - `.failed(.googleBooks, .keyRejected)` → `rejected`
    - Remove → state deleted

13. **The check before saving is one search, `isbn:9781804993750` with `maxResults=1`.** Status 200 means the key works. A rejected key and an unreachable service map as in Decision 10. A failed check leaves the old key in the Keychain unchanged, because the store is written only after a successful check or Save Anyway.

14. **Google Books covers are found by the volume id, and the large image comes from a single-volume GET.** `CoverReference` gains `.googleBooks(volumeID:)`, set only when the list answer has `imageLinks.thumbnail`. A missing `imageLinks` means no cover.
    - Small: the content URL with `zoom=1`.
    - Large: `GET volumes/<id>` (fields `volumeInfo/imageLinks`), then the largest of `extraLarge`, `large`, `medium`, `small` and `thumbnail`.
    - Every image URL is upgraded to `https`, and `edge=curl` is removed.
    - Downloads go through `CoverDownload.fetch` plus `GoogleBooksCover.isPlaceholder`. That check compares the pixel size and byte count of the recorded placeholder fixture (`googlebooks-placeholder`). The constants are taken from that fixture and tested against it.

    Alternative: guess sizes with `zoom=3`. Rejected because large zoom levels return the placeholder for many volumes.

15. **Only printed books count.** A volume whose `printType` is not `BOOK`, or whose `saleInfo.isEbook` is true, is dropped in the mapper, before the match filter, like the other services' carrier filters. Google has no audiobook flag, so audiobooks come out only through `printType` (see Risks).

16. **Google Books lists are never truncated.** `EditionList.isTruncated` uses a per-source limit: DNB 100, Open Library 100, and false for Google Books. Google's `totalItems` is an estimate, and the note's "100 newest records" would be wrong at 40.

17. **Settings is a `Settings` scene with one `Tab`, 620 pt wide.** The scene wrapper is Mac-only (`Mac/SettingsView.swift`). The pane and the help sheet are shared-ready views under `Views/Settings/`, so the iOS app can reuse them later. The sources list is a `ForEach` with `.onMove` inside a grouped `Form` section.

18. **Attribution uses the official graphic, bundled.** `Resources/PoweredByGoogle.png` is downloaded once from `https://books.google.com/googlebooks/images/poweredby.png`, committed, and copied by `make app`. It is loaded through ImageIO from `Bundle.main` as a `CGImage` (no AppKit) and shown in the edition picker. In the Settings pane, the spec's small text "Powered by Google" stands under the key line. The text is not translated and is shown with `Text(verbatim:)`. Each Google Books row in the picker gets `Link` with `Text(verbatim: "Google Books")` to `record.webPage`.

19. **App-wide lookup state lives in one `@Observable @MainActor` object, `BookSources`.** It is created as `@State` in `BuchhalterApp` and injected into both scenes with `.environment(sources)` and `.environment(\.bookLookup, sources.lookup)`. Because it is observable, switching a source on in Settings enables Complete and Find Cover in an open sheet at once. `\.bookLookup` stays the injection point for previews, barcode scanning and the assistant.

20. **The Find Cover alerts get their own window state, `WindowModel.coverAlert`.** The alert is presented by a Mac-only modifier that owns `@Environment(\.openSettings)`, because "Open Settings…" needs the macOS-only action and the generic "Something went wrong" alert has the wrong title.

## Components

### `LookupSource`, `CoverReference`, `LookupRecord`, `LookupError` (changed, `LookupTypes.swift`)
- `LookupSource`:
  - Adds `case googleBooks` (raw `"googleBooks"`) and `CaseIterable`.
  - Adds `var displayName: String`, verbatim and untranslated, used by the Settings rows.
  - Adds `maximumListedRecords: Int?` for `isTruncated`: 100, 100 and nil.
- `CoverReference` adds `.googleBooks(volumeID: String)`.
- `LookupRecord` adds `webPage: URL?`: Google's `canonicalVolumeLink`, else `infoLink`, as https. It is nil for the other sources. The init gets a defaulted parameter, so existing callers are unchanged.
- `LookupError` adds `.keyRejected(LookupSource)` and `.noSourceReached([LookupSource])`. Its doc comment explains which layer throws which case.

### `HTTPClient` (changed)
- `get(_ url: URL, headers: [String: String], timeout: TimeInterval) async throws -> (Data, Int)` becomes the requirement. An extension keeps `get(_:timeout:)` and forwards `[:]` (directional).
- `URLSessionHTTPClient` sets each header plus the User-Agent.
- It must never log a request or its headers.

### `GoogleBooksService` (new, `Lookup/GoogleBooksService.swift`)
- **Responsibility:** URL building, the key header, fetching, error classification and decoding. Mapping is delegated to `GoogleBooksRecordMapper`.
- **State:** `source = .googleBooks`, `client: any HTTPClient`, `keys: any SecretStore`, `static let maximumRecords = 40`, `searchTimeout = 20`.
- **`static func url(for: LookupQuery) -> URL`.**
  - ISBN: `q=isbn:<isbn13>`.
  - Title and author: each word of `DNBService.words(in: title)` as `intitle:<word>`, and each word of the first author's surname (`DNBService.surname(of:)`) as `inauthor:<word>`.
  - The terms are joined with `+`. Each term's value is percent-encoded with the ASCII allow-list DNBService uses, so a `+` in user text cannot split a term.
  - Plus `printType=books`, `maxResults=40`, `projection=full` and `fields=totalItems,items(id,volumeInfo(title,subtitle,authors,publisher,publishedDate,pageCount,language,industryIdentifiers,imageLinks,printType,infoLink,canonicalVolumeLink),saleInfo/isEbook)`.
  - The request goes to `percentEncodedQuery` on `https://www.googleapis.com/books/v1/volumes`.
- **`search(_:)` (`@concurrent`).**
  1. Read the key. Nil or a throw means `.unreachable(.googleBooks)`.
  2. GET with `["X-goog-api-key": key]`.
  3. Cancellation goes through `isCancellation`.
  4. Classify the status per Decision 10, then decode.
  5. Records come from `GoogleBooksRecordMapper.records(from:)`. `totalCount` is `totalItems ?? records.count`.
- **`coverData(for:size:)` (`@concurrent`).** Handles only `.googleBooks(volumeID:)`.
  - Small: the content URL with `zoom=1`.
  - Large: the single-volume GET with the key header, the largest link, then the download.
  - Each image goes through `CoverDownload.fetch` and then `!GoogleBooksCover.isPlaceholder(data)`.
  - Any failure gives nil.
- **`static func checkKey(_ key: String, client:) async -> GoogleBooksKeyCheck`.** Returns `.works`, `.rejected` or `.unreachable`. It runs one search for `isbn:9781804993750` with `maxResults=1`, using the key under test and not the store.
- **Must not:** put the key in a URL, a log or an error. Must not filter matches or sort.

### `GoogleBooksRecordMapper` and `GoogleBooksCover` (new, `Lookup/GoogleBooksRecordMapper.swift`)
- The Decodable shapes for the list and the single volume.
- **`record(from volume)`** returns nil when:
  - `printType` is not `BOOK`
  - `isEbook == true`
  - the title is empty or the id is missing
- **Field mapping:**
  - `id`: `"googlebooks:<volume id>"`, which is also the origin note.
  - Title and subtitle are normalized.
  - Authors go through `LookupMatching.headingToName` (Google gives "Nick Newman").
  - Year: `LookupMatching.year(in: publishedDate)`.
  - Pages: only in 1…99,999.
  - Language: a lowercased 2-letter code, else nil.
  - Publisher.
  - ISBNs: `ISBN_13` and `ISBN_10` through `ISBN.parse`, as ISBN-13, deduplicated, with `isbnDisplay` set to the first.
  - Cover: `.googleBooks(volumeID:)` when `imageLinks.thumbnail` exists.
  - `workCover`: nil.
  - `webPage`.
- **`GoogleBooksCover.bestImageURL(from imageLinks) -> URL?`** upgrades to https and removes `edge=curl`.
- **`GoogleBooksCover.isPlaceholder(_ data: Data) -> Bool`** compares ImageIO pixel size and byte count against the recorded placeholder.

### `SecretStore` (new, `Lookup/SecretStore.swift`)
- `public protocol SecretStore: Sendable` with `read() async throws -> String?`, `save(_ secret: String) async throws`, `delete() async throws`, `exists() async -> Bool` and `suffix() async -> String?` (the last four characters, from the comment attribute or the read). Directional.
- Must not: be implemented in the core with Security.framework.

### `LookupSourceList` (new, `Lookup/LookupSourceList.swift`)
- **State:** `entries: [Entry]`, where `Entry` has `source` and `isOn`. It always holds all three sources, each once.
- **Methods:**
  - `init()`: the default list, DNB on, Open Library on, Google Books off.
  - `init(raw:)` and `raw`.
  - `move(fromOffsets:toOffset:)`, with the same contract as `LibraryListOrder`.
  - `setOn(_:_:)`.
  - `active(hasGoogleKey: Bool) -> [LookupSource]`.
  - `isGoogleBooksLast: Bool`: last among all three entries, which drives "as the last source".
- Must not: know about the Keychain or UserDefaults.

### `GoogleBooksKeyState` and `GoogleBooksKeyLine` (new, `Lookup/GoogleBooksKeyState.swift`)
- `GoogleBooksKeyState: String` with cases `unchecked`, `works`, `rejected`, and `func after(_ event: LookupEvent) -> Self` per Decision 12.
- `GoogleBooksKeyCheck` with cases `works`, `rejected`, `unreachable`.
- `GoogleBooksKeyLine` is the line under the masked key. It is chosen by `static func line(state:isOn:justSaved:isLast:) -> GoogleBooksKeyLine`, with these cases:
  - `nowOnAsLast`
  - `nowOn`
  - `isOn`
  - `isOff`
  - `savedNotChecked`
  - `rejected`

  `justSaved` and `isLast` choose the two "now on" variants. The views map each case to its literal text.

### `BookLookup` (changed)
- **State:**
  - `services: [any BookLookupService]` (the active ones, in order)
  - `observer: (@MainActor @Sendable (LookupEvent) -> Void)?`
  - `var sources: [LookupSource]`
  - `var isEmpty: Bool`
  - `static let live` keeps DNB then Open Library, with no observer.
- **`run(_:preferredLanguage:onEvent:) async throws -> LookupOutcome` (`@concurrent`).** For each service:
  1. Emit `.asking`.
  2. Search.
  3. On a `LookupError`, emit `.failed` and continue.
  4. On an answer, emit `.answered`, then match. 0 matches continues; 1 gives `.single`; more give `.several`.

  After the loop:
  - If at least one source answered, return `.none`.
  - If none answered, throw `.noSourceReached(sourcesAsked)`.
  - With no services, return `.none`, because the UI never calls it.
- **`findCover(_:preferredLanguage:onEvent:) async throws -> Data?`.** Same loop as today over `services`, with the same events. It throws `.noSourceReached` only when no service answered any query.
- **`cover(for:)` and `thumbnail(for:)`** route to `services.first { $0.source == record.source }`, or nil.
- **`EditionList.isTruncated`** uses `source.maximumListedRecords`.
- **Must not:** read settings or the Keychain, or touch the library.

### `LookupMessages` (changed)
- `searching`: two new keys, "Searching Google Books for “\(title)” by \(names)…" and "Searching Google Books for ISBN \(display)…".
- `unreachable(_ sources: [LookupSource])`:
  - One source: the existing DNB and Open Library keys, plus "Can't reach Google Books. Check the internet connection. You can still add the book by hand."
  - Otherwise: "Can't reach any book source. Check the internet connection. You can still add the book by hand."
- `banner`: four Google Books variants, with the same wording as Open Library and the source "Google Books".
- `offerLabel`: "Google Books: \(value)". `coverOffer`: "Use Google Books cover".
- `noCoverMessage(suggestingGoogleBooks: Bool)`: one key without and one key with the second sentence.
- German for every key as in the spec table. Google Books takes no article: "aus Google Books", "in Google Books".

### `KeychainSecretStore` (new, `Sources/Buchhalter/App/KeychainSecretStore.swift`)
- An actor conforming to `SecretStore`, with service `Buchhalter Google Books` and account `api-key`.
- `save` writes `SecItemAdd`, or `SecItemUpdate` when the item exists, with `kSecAttrLabel` "Buchhalter Google Books" and `kSecAttrComment` holding the last four characters.
- `exists` and `suffix` query attributes only. `read` caches the value in memory. `delete` removes the item and clears the cache.
- Must not: set `kSecUseDataProtectionKeychain` yet, print `OSStatus` together with a value, or log anything.

### `BookSources` (new, `Sources/Buchhalter/App/BookSources.swift`)
- `@Observable @MainActor`.
- **State:**
  - `list: LookupSourceList` (UserDefaults `lookupSources`)
  - `keyState: GoogleBooksKeyState?` (UserDefaults `googleBooksKeyState`, nil when there is no key)
  - `hasGoogleKey: Bool` (from `exists()` at launch)
  - `keySuffix: String?`
  - `store: KeychainSecretStore`
- **Derived:**
  - `lookup: BookLookup`: the active services in order, `GoogleBooksService(keys: store)`, and `observer = { [weak self] in self?.record($0) }`.
  - `hasActiveSource`.
  - `suggestsGoogleBooks`: no key, or Google Books off.
- **Methods:**
  - `setOn`, `move`.
  - `record(_ event:)`, which applies `GoogleBooksKeyState.after`.
  - `saveKey(_ text:) async -> GoogleBooksKeyCheck`: trims whitespace, runs `checkKey`, and on `.works` saves, sets `works` and switches Google Books on.
  - `saveWithoutCheck(_ text:) async`: saves, sets `unchecked` and switches it on.
  - `removeKey() async`: deletes, clears the state and switches it off.
  - Keychain write failures surface as `keychainError: String?`.
- **Must not:** hold the full key in observable state, or persist anything about the key outside the Keychain except `googleBooksKeyState`.

### `SettingsView` (new, Mac-only, `Sources/Buchhalter/Mac/SettingsView.swift`)
- `TabView` with `Tab("Book Lookup", systemImage: "magnifyingglass") { BookLookupSettingsPane() }`, `.frame(width: 620)`.
- The scene is added in `BuchhalterApp` as `Settings { SettingsView().environment(sources) }`.

### `BookLookupSettingsPane` (new, `Views/Settings/BookLookupSettingsPane.swift`)
- **Sources section:**
  - The intro line.
  - `ForEach(sources.list.entries)` rows: a checkbox `Toggle`, the name (grey when it has no key), the description or badge on the right, and a `line.3.horizontal` handle.
  - `.onMove` calls `sources.move`.
  - Google Books: badge "Needs a key" or "Set up"; the toggle is disabled without a key.
  - The note under the list.
- **Google Books section:** `GoogleBooksKeySection`, then the `How to get a key…` button presenting `GoogleBooksKeyHelpSheet`, and the Keychain note.
- **Must not:** contain AppKit.

### `GoogleBooksKeySection` (new, `Views/Settings/GoogleBooksKeySection.swift`)
- **Local state:**
  - `phase`: `.entering`, `.checking`, `.rejected`, `.offline`, `.saved`
  - `text`
  - `isChanging`
  - `justSaved`
- **Entering:**
  - A `SecureField` ("Paste your key") and `Save Key`, which is disabled while the text is empty. `.onSubmit` does the same.
  - Checking shows `ProgressView` plus "Checking…", the button disabled, and the line "Saving checks the key with one search at Google Books."
  - Rejected shows a red border and the red message; editing the text returns to `.entering`.
  - Offline shows the amber message and the link button `Save Anyway`.
- **Saved:**
  - "•" × 17 plus the suffix, then `Change…` and `Remove`.
  - The line from `GoogleBooksKeyLine` (green, or red for `.rejected`), then "Powered by Google".
- **Change…** shows an empty field with `Save Key` and `Cancel` (`.cancelAction`, so Esc works) and keeps the old key until the new one checks out.
- **Remove** acts at once, with no confirmation, as the spec says.

### `GoogleBooksKeyHelpSheet` (new, `Views/Settings/GoogleBooksKeyHelpSheet.swift`)
- Title "Get a Google Books Key" / "Google-Books-Schlüssel bekommen".
- Intro, decided by this plan: "The key is free. You need a Google account." / "Der Schlüssel ist kostenlos. Du brauchst ein Google-Konto."
- The six numbered steps from the spec.
- Footer:
  - `Open Google Cloud Console` uses `openURL` with `https://console.cloud.google.com/` and leaves the sheet open.
  - `Done` uses `.defaultAction`, and a hidden `.cancelAction` makes Esc close the sheet too.

### `PoweredByGoogleMark` (new, `Views/Common/PoweredByGoogleMark.swift`)
- Loads `PoweredByGoogle.png` from `Bundle.main` through `CGImageSourceCreateWithURL` once (static), and shows it as `Image(decorative:scale:)`.
- Accessibility label: verbatim "powered by Google".

### `LookupModel` (changed)
- `start` sets `.running(query, lookup.sources.first ?? .dnb)`. `onEvent(.asking(source))` updates the status line.
- `catch .noSourceReached(let sources)` sets `.unreachable(query, sources)`, and the phase now carries `[LookupSource]`.

### `LookupHeader`, `BookEditorSheet` (changed)
- `LookupHeader` takes `hasSources: Bool`. Complete is disabled when `!hasSources || !canComplete`.
- Tooltip: "Turn on a source in Settings" when there is no source, else the existing one.
- The new grey line: "Type a title and author, or an ISBN. Complete looks up the rest in your book sources, including the cover."
- `BookEditorSheet` reads `@Environment(BookSources.self)` for `hasActiveSource`.

### `EditionPickerSheet` (changed)
- When `list.source == .googleBooks`, the headline block shows `PoweredByGoogleMark` on the right.
- Each row with `record.webPage` gets a trailing `Link` with `Text(verbatim: "Google Books")`. It is white on the selected row, accent otherwise.

### `BookDetailView`, `WindowModel`, `FindCoverAlertModifier` (changed and new)
- `WindowModel.coverAlert: CoverAlert?` with cases `.noCover(suggestsGoogleBooks: Bool)` and `.noSourceReached`.
- `findCover`:
  - Nil sets `.noCover(suggestsGoogleBooks: sources.suggestsGoogleBooks)`.
  - `LookupError.noSourceReached` sets `.noSourceReached`.
  - The old `errorMessage` texts are removed.
- The Find Cover button and the context-menu item are also disabled when `!sources.hasActiveSource`, with `.help("Turn on a source in Settings")`. macOS shows no tooltip on menu items, which is accepted.
- `Mac/FindCoverAlertModifier.swift` (new, Mac-only) presents the alerts:
  - "No cover found" with the message from `LookupMessages.noCoverMessage`, plus `Open Settings…` (default, calls `openSettings()`) and `OK` when Google Books is suggested.
  - "Can't reach any book source" with "Check the internet connection." and `OK`.
- `RootView` applies the modifier.

## Interactions

**Launch** (main actor)
1. `BuchhalterApp.init` creates `BookSources`, which reads `lookupSources` and `googleBooksKeyState` from UserDefaults.
2. A task runs `store.exists()` and `store.suffix()`. These are attribute-only queries and do not prompt.
3. The `Window` and `Settings` scenes get `.environment(sources)`. `RootView` gets `.environment(\.bookLookup, sources.lookup)`.

**Settings: toggle and drag**
- Toggle or `onMove` calls `sources.setOn` or `sources.move`. The list mutates and writes the raw string to UserDefaults.
- `lookup` recomputes. Open sheets re-render: Complete and Find Cover enable or disable at once.

**Save Key**
1. The pane sets `.checking` and awaits `sources.saveKey(text)`.
2. `GoogleBooksService.checkKey` runs `@concurrent` off the main actor, with one HTTP GET and the key in the header.
3. The result comes back on the main actor:
   - `.works`: `store.save` (actor) → `hasGoogleKey = true`, `keySuffix`, `keyState = .works`, `list.setOn(.googleBooks, true)` → the pane shows `.saved` with `justSaved = true`.
   - `.rejected`: the pane shows `.rejected`. Nothing is written, and the old key, if any, stays.
   - `.unreachable`: the pane shows `.offline`. `Save Anyway` runs `saveWithoutCheck` and the state becomes `unchecked`. `Save Key` checks again.

**Change and Remove**
- `Change…` sets `isChanging` and shows an empty field. A save runs the same flow, and only success overwrites the old key. `Cancel` or Esc returns to `.saved`.
- `Remove` runs `store.delete()`, sets `keyState = nil`, `hasGoogleKey = false` and `list.setOn(.googleBooks, false)`. The place in the list is kept.

**Complete**
1. `BookEditorSheet.complete` calls `LookupModel.start(query, …, using: bookLookup)`.
2. A `Task` calls `bookLookup.run` (`@concurrent`). For each active service in order:
   1. `onEvent(.asking)` runs on the main actor and updates the status line.
   2. `service.search` runs off the main actor. Google reads the key here, cached, prompting once per build.
   3. An error emits `.failed` (observer → `BookSources.record` → maybe `rejected`), and the loop continues.
   4. An answer emits `.answered` (observer → `works`), then match: 0 continues, 1 gives `.single`, more give `.several`.
3. Afterwards, on the main actor:
   - `.single`: `fill` → `lookup.cover(for:)`, routed to the record's service.
   - `.several`: `EditionPickerSheet`, with the logo and links for Google Books.
   - `.none`: the amber hint.
   - `.noSourceReached(sources)`: the red hint, naming one source or "any".

**Find Cover**
1. `BookDetailView.findCover` calls `bookLookup.findCover(queries)`. It loops queries, then services, then edition covers, then work covers. Google covers come through the single-volume GET, the download and the placeholder check.
2. Afterwards, on the main actor:
   - Data, with the cover still empty, calls `library.setCover`.
   - Nil sets `coverAlert = .noCover(suggestsGoogleBooks:)`.
   - `.noSourceReached` sets `coverAlert = .noSourceReached`.
3. `Open Settings…` calls `openSettings()`, which opens the Settings window on Book Lookup, its only tab.

**Every source off**
- `sources.lookup.isEmpty` is true, so `hasActiveSource` is false.
- `LookupHeader` and `BookDetailView` disable their controls and show the tooltip. Switching a source on reverses this through observation.

## Changes by file

| File | New/changed | Change |
|---|---|---|
| `Sources/BuchhalterCore/Lookup/LookupTypes.swift` | changed | `.googleBooks`, `CaseIterable`, `displayName`, `maximumListedRecords`; `CoverReference.googleBooks(volumeID:)`; `LookupRecord.webPage`; `LookupError.keyRejected` and `.noSourceReached` |
| `Sources/BuchhalterCore/Lookup/HTTPClient.swift` | changed | `headers` parameter, forwarding extension, headers set in `URLSessionHTTPClient` |
| `Sources/BuchhalterCore/Lookup/BookLookupService.swift` | changed | Doc: services throw `.unreachable` or `.keyRejected` |
| `Sources/BuchhalterCore/Lookup/BookLookup.swift` | changed | Ordered `services`, `observer`, `LookupEvent`, skip-on-failure `run`, `findCover` over services, routing by source, per-source `isTruncated` |
| `Sources/BuchhalterCore/Lookup/GoogleBooksService.swift` | new | URL, header, error classification, search, covers, `checkKey` |
| `Sources/BuchhalterCore/Lookup/GoogleBooksRecordMapper.swift` | new | Decoding, print filter, mapping, `GoogleBooksCover` (best URL, https, placeholder) |
| `Sources/BuchhalterCore/Lookup/SecretStore.swift` | new | `SecretStore` protocol |
| `Sources/BuchhalterCore/Lookup/LookupSourceList.swift` | new | Order and switches, raw parsing, move, active sources |
| `Sources/BuchhalterCore/Lookup/GoogleBooksKeyState.swift` | new | Key state, transitions, `GoogleBooksKeyCheck`, `GoogleBooksKeyLine` |
| `Sources/BuchhalterCore/Lookup/LookupMessages.swift` | changed | Google Books keys, `unreachable([LookupSource])`, `noCoverMessage` |
| `Sources/Buchhalter/App/BuchhalterApp.swift` | changed | `@State BookSources`, environment on the Window, `Settings` scene |
| `Sources/Buchhalter/App/BookSources.swift` | new | App-wide sources, key and state, builds `BookLookup` |
| `Sources/Buchhalter/App/KeychainSecretStore.swift` | new | Keychain actor, service `Buchhalter Google Books`, account `api-key` |
| `Sources/Buchhalter/App/WindowModel.swift` | changed | `coverAlert: CoverAlert?` |
| `Sources/Buchhalter/Mac/SettingsView.swift` | new | Settings `TabView`, 620 pt |
| `Sources/Buchhalter/Mac/FindCoverAlertModifier.swift` | new | Both Find Cover alerts, `openSettings` |
| `Sources/Buchhalter/Views/Settings/BookLookupSettingsPane.swift` | new | Sources list and Google Books group |
| `Sources/Buchhalter/Views/Settings/GoogleBooksKeySection.swift` | new | Key entry states, masked key, lines |
| `Sources/Buchhalter/Views/Settings/GoogleBooksKeyHelpSheet.swift` | new | Help sheet |
| `Sources/Buchhalter/Views/Common/PoweredByGoogleMark.swift` | new | Bundled graphic through ImageIO |
| `Sources/Buchhalter/Views/Common/LibraryEnvironment.swift` | changed | Doc for `\.bookLookup` (set from `BookSources`) |
| `Sources/Buchhalter/Views/RootView.swift` | changed | Applies `FindCoverAlertModifier` |
| `Sources/Buchhalter/Views/Detail/BookDetailView.swift` | changed | `coverAlert`, disabled when there is no source, tooltip, doc comment |
| `Sources/Buchhalter/Views/Sheets/BookEditorSheet.swift` | changed | Passes `hasSources` |
| `Sources/Buchhalter/Views/Sheets/Lookup/LookupHeader.swift` | changed | No-source tooltip, new grey line, unreachable with sources |
| `Sources/Buchhalter/Views/Sheets/Lookup/LookupModel.swift` | changed | First active source, `onEvent`, `.unreachable(query, [LookupSource])` |
| `Sources/Buchhalter/Views/Sheets/Lookup/EditionPickerSheet.swift` | changed | Logo and per-row `Google Books` link |
| `Resources/PoweredByGoogle.png` | new | Official attribution graphic (downloaded once) |
| `Makefile` | changed | `app` copies `PoweredByGoogle.png` into `Contents/Resources` |
| `Resources/Localizable.xcstrings` | changed | New keys in en and de. The obsolete keys are removed: the old grey line, "No cover found for this book." and "Can't reach the Deutsche Nationalbibliothek or Open Library…" |
| `Tests/BuchhalterCoreTests/LookupTestSupport.swift` | changed | `FakeHTTPClient` records headers; `FakeSecretStore`; `makeRecord` prefix for Google |
| `Tests/BuchhalterCoreTests/BookLookupTests.swift` | changed | Coordinator tests for ordered services, skipping, events |
| `Tests/BuchhalterCoreTests/GoogleBooksTests.swift` | new | URL, header, classification, mapping, covers, check |
| `Tests/BuchhalterCoreTests/LookupSourceListTests.swift` | new | Parsing, move, active sources |
| `Tests/BuchhalterCoreTests/GoogleBooksKeyStateTests.swift` | new | Transitions and line choice |
| `Tests/BuchhalterCoreTests/LookupMessagesTests.swift` | changed | Google Books sentences, unreachable with one or several sources |
| `Tests/BuchhalterCoreTests/LocalizationCatalogTests.swift` | changed | The spec's new German terms |
| `Tests/BuchhalterCoreTests/Fixtures/googlebooks-*` | new | Recorded answers, listed under Testing |
| `docs/dev/architecture.md` | changed | See below |
| `AGENTS.md` | changed | Opening and Quick facts: Google Books built, Settings window, Mac App Store planned |

The `docs/dev/architecture.md` changes:
- Targets and Layout: `Views/Settings`, `Mac/SettingsView`, the Keychain store.
- Data flow: lookup events, skip-on-failure.
- UI structure: the Settings scene now exists.
- Mac view state: `lookupSources`, `googleBooksKeyState`.
- Book lookup section: three sources, user order, skipping.
- Decision 15 replaced by "user-ordered sources, skip on failure".
- New decisions: key in the Keychain with a header; `BookSources`.
- Open points: data-protection keychain and sandbox.

## Testing

**Fixtures to record first**, read-only against Google, with approval:

| File | Request |
|---|---|
| `googlebooks-isbn-garden.json` | `q=isbn:9781804993750` with the full parameter set. It must contain "The Garden" by Nick Newman with `imageLinks` |
| `googlebooks-stoner-williams.json` | `q=intitle:stoner+inauthor:williams`: several editions, some e-books |
| `googlebooks-no-match.json` | An ISBN with no volume, giving `totalItems` 0 and no `items` |
| `googlebooks-volume-garden.json` | `GET volumes/<id>` with `fields=volumeInfo/imageLinks` |
| `googlebooks-error-invalid-key.json` | The header set to `invalid-key-for-fixture`; the status is recorded too |
| `googlebooks-error-quota.json` | Keyless: the 429 answer |
| `googlebooks-placeholder` | The content URL with `zoom=1` for a volume without `imageLinks`, saved with its real extension |

The key is never typed or echoed. It is piped as a header from the Keychain, as directional shell:

```
security find-generic-password -s "Buchhalter Google Books" -a api-key -w \
  | sed 's/^/X-goog-api-key: /' \
  | curl -sS -H @- -w '%{http_code}\n' -o Tests/BuchhalterCoreTests/Fixtures/googlebooks-isbn-garden.json \
    'https://www.googleapis.com/books/v1/volumes?q=isbn:9781804993750&printType=books&maxResults=40&projection=full&fields=…'
```

After recording, `grep -c -F -f <(security find-generic-password -s "Buchhalter Google Books" -a api-key -w) Tests/BuchhalterCoreTests/Fixtures/googlebooks-*` must print 0 for every file. The recordings confirm the header, `fields` and the error codes. Decisions 8 and 10 are adjusted only if they contradict them.

**Unit tests (`swift test`)**

`GoogleBooksTests` proves that:
- The ISBN and title-author URLs carry `intitle:`/`inauthor:` per word, encode non-ASCII and `+`, and contain no key.
- The key goes in `X-goog-api-key`, checked through `FakeHTTPClient`.
- A missing key or a failing `FakeSecretStore` gives `.unreachable` and makes no request.
- 401, 403 and 429 give `.keyRejected`. A 400 with the invalid-key fixture gives `.keyRejected`. A 400 with another body, a 500, a transport error and garbage all give `.unreachable`. Cancellation stays cancellation.
- The Garden fixture maps title, authors, year, pages, language, publisher, ISBN-13, the cover reference and an https `webPage`.
- E-books and magazines are dropped.
- The no-match fixture gives no records.
- The large cover takes the largest `imageLinks` URL from the volume fixture, as https and without `edge=curl`.
- The placeholder fixture is rejected and a real JPEG is accepted.
- `checkKey` maps 200, the rejection and failure.

`BookLookupTests` (rewritten coordinator part) proves that:
- The order of `services` is the order asked.
- A failing first source is skipped and the second fills.
- Every source failing throws `.noSourceReached` with the sources asked.
- One answered plus one failed with no match gives `.none`.
- Events arrive in the order asking, failed/answered.
- `observer` and `onEvent` both get them.
- `findCover` walks the user's order and skips failures.
- Covers and thumbnails route to the record's source.
- An empty `services` returns `.none`.
- Google lists are not truncated.

`LookupSourceListTests` proves:
- The default order and switches.
- A round trip through the raw value.
- Damaged values: unknown, repeated and missing entries.
- `move` with the `onMove` contract.
- `active(hasGoogleKey:)` excludes Google Books without a key, and `isGoogleBooksLast`.

`GoogleBooksKeyStateTests` proves every transition in Decision 12 and every `GoogleBooksKeyLine` choice, including "now on, as the last source" against "now on".

`LookupMessagesTests` covers the Google Books variants of searching, banner, offer and cover offer, `unreachable` with one source (each of the three) and with several, and both `noCoverMessage` forms.

`LocalizationCatalogTests` adds the spec's German terms, such as "Schlüssel nötig", "Eingerichtet", "Schlüssel sichern" and "Trotzdem sichern".

**Commands:** `make strings`, then translate the new keys and delete the obsolete ones in `Resources/Localizable.xcstrings`. Then `swift test` and `make app`. The agent stops after `make app`. The user starts the app.

**Manual checks for the user**, on the real library, with `open build/Buchhalter.app`, once more in German with `open build/Buchhalter.app --args -AppleLanguages '(de)'`. The first Google lookup after each build shows the Keychain prompt; choose "Always Allow".
1. ⌘, and `Buchhalter → Settings…` open "Book Lookup" at 620 pt. ⌘, again brings the window to the front.
2. Fresh state: DNB on, Open Library on, Google Books last, grey and disabled, with "Needs a key".
3. Paste a wrong key, then Save Key: "Checking…", then the red message and border. Editing the field clears them. The key is not saved.
4. Paste the real key, then Return: masked "•••…" plus the last four, "Set up", Google Books on, and "The key works. Google Books is now on, as the last source." Closing and reopening the window shows "…is on."
5. Wi-Fi off, Change…, paste the key, Save Key: the amber message and Save Anyway. Esc keeps the old key.
6. Drag Google Books to the top, uncheck Open Library, then Complete for "The Garden" / Nick Newman: the status line names Google Books first, and the banner and notes say "Google Books".
7. A title search with several Google results: the picker shows the "powered by Google" graphic, and each row's `Google Books` link opens the book's page.
8. Find Cover on "The Garden" (ISBN 978-1-80499-375-0) finds the cover.
9. Google Books off, then Find Cover on a book with no cover anywhere: "No cover found" with the Google Books sentence and `Open Settings…`, which opens the pane.
10. Wi-Fi off, then Complete: the red "Can't reach any book source" appears only after all sources have failed. Find Cover shows "Can't reach any book source".
11. Every source off: Complete and Find Cover are disabled with "Turn on a source in Settings". Turning one on with Add Book open enables Complete at once.
12. Remove: Google Books goes off and disabled, "Needs a key", its place is kept. Quit and relaunch: order, switches and key state are kept.
13. How to get a key…: the steps, `Open Google Cloud Console` opens the browser and leaves the sheet open, and Done, Return and Esc close it.

## Permissions

| Action | Status | User's choice |
|---|---|---|
| `swift build`, `swift test`, `make app`, `make strings`, `xcrun xcstringstool` | allowed (project settings) | — |
| `gcloud projects create buchhalter-books-2026 --name=Buchhalter`, `gcloud services enable books.googleapis.com --project=buchhalter-books-2026`, `gcloud services api-keys create --display-name="Buchhalter Books" --api-target=service=books.googleapis.com --project=buchhalter-books-2026` (append a suffix if the project id is taken) | prompts | The main session runs them before implementation, approved per call. They create a cloud project and key (a cloud write, reversible by deleting the project) |
| `gcloud auth login` | interactive | The user runs it (`! gcloud auth login`) |
| `security add-generic-password -U -s "Buchhalter Google Books" -a api-key -w "$(gcloud services api-keys get-key-string <key id> --project=buchhalter-books-2026 --format='value(keyString)')"` | prompts | The main session runs it, approved per call. It writes one item to the login Keychain. The key is in that process's argv briefly, on this Mac only |
| `security find-generic-password … -w` inside a pipe or process substitution, for fixtures and the grep check | prompts | Approved per call. The output never goes to the terminal or a file |
| `curl` to `www.googleapis.com` and `books.google.com` (fixtures, placeholder, `PoweredByGoogle.png`) | prompts | Approved per call |
| WebFetch/WebSearch for documentation | allowed (user settings) | — |
| Starting the app | never by an agent | The user starts it on the real library |
| Commit or push | only when the user asks | — |

## Risks and open points

- **Irreversible and destructive changes:**
  - `Remove` deletes the Keychain item at once, without confirmation. That is spec behaviour, and the key stays recoverable from the Google Cloud Console.
  - The obsolete catalog keys are deleted from `Localizable.xcstrings` (a repo edit).
  - The gcloud project and key are cloud writes, done only by the main session.
  - The SwiftData store and the library are not touched.
- **Keychain prompts:** each ad-hoc build prompts on the first secret read, and denying makes Google Books unreachable for that session's lookups. Open point: move to the data-protection keychain (`kSecUseDataProtectionKeychain` plus a `keychain-access-groups` entitlement) when the Developer account, proper signing and the App Store sandbox arrive. The sandbox also needs `com.apple.security.network.client`.
- **Header and `fields`:** if the recordings show that the Books API rejects `X-goog-api-key` or ignores `fields`, the implementer falls back as stated in Decisions 8 and 14 and records the reason in the architecture doc.
- **Branding conflict:** Google's terms forbid reordering or altering results. The app filters to printed matches and shows newest first, as the spec requires. This is a deliberate interpretation for a lookup aid, and the architecture doc records it.
- **Audiobooks and e-books:** Google has no audiobook flag. `printType` and `isEbook` are the only filters. `isEbook == true` can, in rare cases, mark a volume that is also in print. Dropping it is accepted.
- **Placeholder detection** depends on the recorded image. If Google changes the picture, the JPEG/PNG check and the size check may let it through. The fixture test documents the current one.
- **Quota:** a fresh key has 1,000 requests a day by default. A large Find Cover uses one search per query and up to one volume GET per candidate. A used-up quota shows as a rejected key (red line), as the spec says.
- **`Form` with `onMove`:** if a grouped `Form` section does not support dragging on macOS 27, the implementer uses a bordered `List` with fixed height (three rows) inside the section. The look follows the design artboard `SettingsLookup`.
- **Texts this plan added:** the help sheet's intro ("The key is free. You need a Google account." / "Der Schlüssel ist kostenlos. Du brauchst ein Google-Konto.") and a Keychain write error ("The key couldn't be saved in the Keychain." / "Der Schlüssel konnte nicht im Schlüsselbund gesichert werden."). The user confirms them at the manual check.
- **Left to the implementer:** where exactly the logo sits in the picker header, the colour of the `Google Books` link on selected rows, and whether `KeychainSecretStore` keeps the cached value until quit or clears it on Remove only. Remove must clear it.