# Book lookup

Complete in Add and Edit Book pulls a book's data, cover and synopsis, by a valid ISBN or by title and author. Find Cover fetches only a cover, Find Synopsis only a synopsis. Overview: [architecture.md](architecture.md).

## Sources

- The Deutsche Nationalbibliothek (SRU, MARC 21 over XML, anonymous), Open Library (anonymous) and Google Books (API v1, the user's own key). Covers come from the DNB's MVB cover service (undocumented; any failure means no cover), Open Library's covers API or Google's content URLs.
- The user switches each on or off and drags them into an order in Settings (`LookupSourceList`, saved per device as `lookupSources`). A new user starts with DNB, Open Library, then Google Books, off until a key is saved.
- Complete asks the sources that are on, top to bottom; the first that finds the book supplies the result. A source that cannot be reached (offline, timeout, server error, a key Google refuses) is skipped. Only when every source asked has failed does Complete show the red hint ("Can't reach any book source", or the source's name when only one was asked).
- When no source is on, Complete, Find Cover and Find Synopsis are disabled.

## Layers

- `HTTPClient` (ephemeral `URLSession`, User-Agent "Buchhalter/0.1 (personal book app)") and `BookLookupService` (`DNBService`, `OpenLibraryService`, `GoogleBooksService`) are protocols with fakes; parsers and URL building are tested against recorded answers in `Fixtures/`.
- `MARCXMLParser` reads structure, `DNBRecordMapper` applies the bibliographic rules, `LookupMatching` filters real matches and orders editions (newest first), `BookLookup` is the coordinator, `LookupMerge` merges a record into a `BookDraft`, `LookupMessages` holds every sentence.
- `BookSources` (`@Observable`, one per app) builds `BookLookup` from the user's list and is injected as `\.bookLookup`, so a switch in Settings enables Complete in an open sheet at once.

## Flow

`LookupModel` (one per editor sheet) runs `BookLookup.run` (`@concurrent`) in a task. Each source reports `LookupEvent`s (`asking`, `answered`, `failed`) on the main actor: to the status line, and to the observer that keeps the Google Books key state (`works`, `rejected`) current. Parsing and matching run off the main actor; only value types (`LookupRecord`, `EditionList`, `LookupOutcome`) come back. A `generation` check after every await drops a late answer after Stop, Save, Cancel or a newer Complete. Author resolution and the merge run on the main actor against the draft as it is then, so values typed meanwhile win. Nothing is saved during a lookup; the book is saved as one undo step.

**Merge rule:** an empty field is filled, an equal one stays, a different one keeps the user's value and is offered ("DNB: 2009 · Use"). A typed title is only offered. Status, dates, rating, notes and collections are never touched. The highlights, notes and Undo are derived from `LookupResult` and the current draft, not stored per field.

Several matches open `EditionPickerSheet`. A book added after a lookup has origin `lookup` and the record id in its origin note. Covers are downloaded once into the book, so the library works offline and syncs with them. The Mac app has `com.apple.security.network.client`.

## Synopsis

- **Where the text is:** `LookupRecord.synopsis` is a `SynopsisReference`. DNB: the publisher's blurb linked in field 856 with `$3` "Inhaltstext" (`.dnbBlurb`; any DNB host — services.dnb.de, deposit.dnb.de, d-nb.info — always over https; a small HTML page with one `div`), else the first 520 summary (`.text`, without "Zusammenfassung: " and "--(Provided by publisher.)"). Google Books: `volumeInfo.description` from the same answer (`.text`, HTML turned into text). Open Library: the work's description (`.openLibraryWork(key:)`, `/works/<id>.json`, a string or `{value}`). `BookLookupService.synopsis(for:)` downloads lazily and returns nil on any failure, like covers; a PDF behind a DNB link counts as none.
- **Plain text:** `SynopsisText.plain(fromHTML:)` turns block tags and `<br>` into line breaks, drops other tags, decodes entities and keeps at most one empty line between paragraphs.
- **Which text:** `BookLookup.findSynopsis(queries, first:, bookLanguage:)` tries `first` (Complete's record) before anything else, then each query against each source in the user's order, at most 3 matching editions per source and query. A text's language is its record's (the sources tag the edition, not the text); Open Library's work text is untagged. `SynopsisChoice` returns the first text in the book's language at once and otherwise the first text found. It throws `noSourceReached` only when no source answered and nothing was found.
- **Complete and the scan card** fetch the cover and the synopsis concurrently (`async let`) and pass the synopsis to the merge, where `LookupField.synopsis` fills an empty one, offers a different one ("Google Books has a different synopsis · Show · Use") and counts in the banner. The comparison folds case and whitespace. A failed synopsis search never fails Complete.
- **Find Synopsis** is in the row menu and the cover menu of a book without a synopsis (`BookFinder`, `WindowModel.findingSynopsis`). It searches like Find Cover, saves with `Library.setSynopsis` as one undo step ("Find Synopsis"; clearing is "Remove Synopsis"), and ends in `FindAlert.noSynopsis` or `.noSourceReached`. A synopsis typed meanwhile wins.
- **The source** is stored with the text and drives the "From …" line; the editor clears it whenever the text changes, so an edited text is the user's.

## Find Cover

Offered over a book without a cover (on hover on the Mac, on a tap on iOS) and in the cover's context menu (`BookLookup.findCover`). It searches by the ISBN, then by title and authors (`LookupQuery.coverQueries`, the title cut at the first colon or parenthesis). Each search asks every source that is on and takes the first cover that downloads: the matching editions' own covers first (at most 5 per source and search), then Open Library's work cover, which can show another edition. Unlike Complete it falls through to the next source when one has no cover. No cover gives "No cover found", with an Open Settings… button when Google Books has no key or is off. A cover set by hand while it runs wins.

## Google Books

- **Key:** a generic password, service `Buchhalter Google Books`, account `api-key`, with `kSecAttrComment` holding the last four characters, so the masked key shows without reading the secret. `KeychainSecretStore` (an actor) caches the secret after the first read; it is read only when Google Books is asked, and never goes into the store, a file, a URL or a log.
- **iCloud Keychain:** both apps use `.synchronized(accessGroup: "3PT9KVM9AJ.de.juergenalbertsen.buchhalter")` (`kSecAttrSynchronizable`, `kSecAttrAccessibleAfterFirstUnlock`), so a key saved on one device is on all of the user's devices. `BookSources.refreshKey()` runs at launch and whenever the app becomes active, after `migrateIfNeeded()`: with no synchronized item, it copies the older data protection item, then the file-based login keychain item, into iCloud Keychain and deletes the data protection item. Remove deletes the item everywhere. `buchhalter-cli` uses the file-based item (`.fileBased`), where macOS asks once per build.
- **Request:** `GET https://www.googleapis.com/books/v1/volumes` with `q=isbn:<isbn13>` or `intitle:`/`inauthor:` terms, `printType=books`, `maxResults=40`, `projection=full` and a `fields` list. The key goes in the `X-goog-api-key` header.
- **Failures:** 401, 403 and 429 mean a rejected key; 400 only when the answer names the key; anything else is unreachable. A rejected key turns the Settings line red but leaves Google Books on.
- **Checking a key:** Save Key runs one search (`isbn:9781804993750`, `maxResults=1`) before saving. Works: saved, Google Books on. Rejected: nothing saved. Unreachable: Save Anyway saves it unchecked.
- **Records:** printed books only (`printType` `BOOK`, not `isEbook`). A role in brackets is cut from authors, "pt-BR" gives "pt", 0 pages means none. The record id is "googlebooks:<volume id>".
- **Covers:** large means the content URL with `zoom=3`, then `zoom=2`, then the single-volume request's largest link. Google answers a volume without a scan with grey placeholders; `GoogleBooksCover.isPlaceholder` recognizes them by pixel size and byte count (recorded in `googlebooks-placeholder*.png`).
- **Branding:** the edition picker shows "powered by Google" (`PoweredByGoogleMark`) and a `Google Books` link on every Google row. Lists are never truncated, because `totalItems` is an estimate (`LookupSource.maximumListedRecords`).

## Decisions

- **User-ordered sources, a failing source is skipped.** The user chooses the order, so a mostly English source does not quietly fill a German library, and an outage of one source does not block the others.
- **Lookup ids in `originNote`, not a new attribute.** Nothing reads them, so a schema version and a migration of the real library would buy nothing.
- **The merge is derived, not flagged,** so highlights, notes and Undo cannot drift from what the user edits.
- **The key in the Keychain, sent in a header.** Keys stay out of the store, files and logs (AGENTS.md); the header also keeps it out of URLs, errors and fixtures. The Keychain code is its own target because the core imports only Foundation and SwiftData.
- **The text's language is its edition's.** No language detection: the sources tag editions, and trusting the tag is right in nearly every case without another framework in the core (user's choice).
- **Synopses are fetched lazily, like covers.** A search stays one request per source; only the record that is used costs a download.
- **The synopsis is a lookup field.** The merge, banner, highlight, offer and Undo already work per field.
- **iCloud Keychain for the key.** The user enters it once for every device. The CLI keeps the file-based item: a command line tool has no provisioning profile for an access group.
