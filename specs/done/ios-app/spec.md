# iOS App

Buchhalter on iPhone and iPad: the same library as on the Mac, through iCloud, with everything the Mac app does, plus a barcode scanner that uses the device's own camera.

Design: https://claude.ai/artifact/KWjhfRAqkfyM8d4sYB3ggT (section "iPhone App"; the scan card also in "Barcode Scanning", artboard "Scan Barcode · iPhone")

## Problem

1. The library is only on the Mac. Away from the desk (in a bookshop, on the sofa, at a friend's shelf) there is no way to check whether a book is already in it, to mark a book as started or finished, or to note one to read.
2. Scanning on the Mac means holding a book up to the built-in camera, which has a fixed focus, or to an iPhone used as the Mac's camera. The iPhone's own camera reads barcodes close up and reliably, and it is where the books are.
3. The library already syncs through iCloud (`iCloud Sync`), but only the Mac uses it.

## Experience

### Getting the app

One app runs on iPhone and iPad. It needs iOS 27 or iPadOS 27.

A `make` target builds the app and installs it on the iPhone (or iPad), over cable or over Wi-Fi when the device is paired. It is signed with the same development certificate as the Mac app, and the development profile lists the user's iPhone and iPad. The app opens the same iCloud library (CloudKit Production) as the Mac app. There is no TestFlight build in this spec.

On iPhone the app runs in portrait only. On iPad it runs in every orientation.

### First launch

The first launch opens the Library screen at once. While the library is still coming from iCloud, the lists fill in as the books arrive, and a note sits above the bottom bar:

- "Downloading your library from iCloud…" / "Deine Bibliothek wird aus iCloud geladen…"
- "Books appear as they arrive. Covers can take a few minutes." / "Bücher erscheinen, sobald sie ankommen. Coverbilder können ein paar Minuten dauern."

The note disappears when the first download is done, by the same rule as on the Mac (20 seconds without new data).

When the device is not signed in to iCloud, or iCloud is off for Buchhalter, the Library screen shows instead:

- "Your library is in iCloud" / "Deine Bibliothek ist in iCloud"
- "Sign in to iCloud on this iPhone, or turn on iCloud for Buchhalter, to see the books from your Mac." / "Melde dich auf diesem iPhone bei iCloud an oder schalte iCloud für Buchhalter ein, um die Bücher von deinem Mac zu sehen." (On iPad: "this iPad" / "diesem iPad".)
- `Open Settings` / `Einstellungen öffnen`, which opens the iOS Settings app.
- "Books you add now stay on this iPhone and go to iCloud once you sign in." / "Bücher, die du jetzt hinzufügst, bleiben auf diesem iPhone und kommen nach iCloud, sobald du dich anmeldest."

The app works without iCloud. Books added then sync after the user signs in.

### The Library screen (iPhone)

The start screen has the large title "Library" / "Bibliothek". From top to bottom:

- A gear button (Settings) at the top left and `Edit` / `Bearbeiten` at the top right.
- A search field "Search All Books" / "Alle Bücher durchsuchen". Typing searches every book, by the same rules as the Mac's search (title, authors, ISBN, German folding, so "boll" finds "Böll").
- "Library" / "Bibliothek": Reading, Want to Read, Read, All Books, in the order set on the Mac, each with its count.
- "Collections" / "Sammlungen": the user's collections, each with its count.
- A bottom bar with `New Collection` / `Neue Sammlung`, a Scan Barcode button and a green `+` (Add Book).

`Edit` lets the user drag the built-in lists and the collections into a new order, and delete a collection (with the Mac's confirmation). The order syncs, as on the Mac. A long press on a collection offers `Rename` / `Umbenennen` and `Delete Collection…` / `Sammlung löschen…`.

During a first upload or download, or when sync has a problem, the line the Mac shows at the bottom of its sidebar appears above the bottom bar. Tapping it opens Settings at iCloud.

### A list

Tapping a list opens it: the large title (the list's name), a line "2 books · Sort: Author, Year" (plural rules), a search field for this list, and the books as rows with cover, title, authors and the Mac's third line ("Started 3 Oct 2026").

At the top right:

- A sort and view button. Its menu has `List` / `Liste` and `Grid` / `Raster` (the view mode of this list, as on the Mac) and `Sort Books…` / `Bücher sortieren…`, which opens the Mac's sort levels as a sheet. Sorting applies to every list and collection, and it syncs.
- `+` (Add Book). Added from a collection, the book is preset to that collection; from Want to Read or Reading, to that status; as on the Mac.

The grid shows the covers, three in a row on iPhone. An empty list shows the Mac's empty state.

### Row actions

- **Slide right** shows the next step for the book's current status. Want to Read gives `Start Reading` / `Lesen beginnen`: it starts a reading dated today. Reading gives `Finish Reading…` / `Fertig gelesen…`, which opens Finish Reading. Read, Abandoned and books without a status have no next step.
- **Slide left** shows `Delete` / `Löschen`. It asks first, with the Mac's confirmation for `Delete Book…`.
- **Long press** opens the Mac's right-click menu for the book: Start Reading (for Want to Read), Finish Reading…, Abandon…, Read Again, Edit, Add to Collection, Remove from "…" (in a collection), Find Cover, Delete Book….

### Book detail

Tapping a row opens the book. The content is the Mac's detail, stacked for a narrow screen:

- The cover, centred, then title, subtitle, authors, and the line with year, pages, language and ISBN.
- The status badge ("Reading since 3 Oct 2026").
- The buttons for the status: `Start Reading` / `Lesen beginnen` and `Edit` for a book in Want to Read; `Finish Reading…`, `Abandon` and `Edit` for a book being read; `Read Again` for a finished one; as on the Mac. When the German labels do not fit on one line, the main button takes the full width and the other two share the row below.
- "Collections" / "Sammlungen" with the book's collections as chips and `+ Add to Collection` / `+ Zu Sammlung hinzufügen`.
- "Readings" / "Lektüren", newest first. Tapping a reading opens it for editing (dates, rating, notes), as on the Mac.

Tapping the title, subtitle, authors, year, pages, publisher or ISBN edits it in place, with the Mac's rules: Return or tapping elsewhere saves, an invalid value keeps the field open with a red outline. Languages and Date Added open their pickers.

The `⋯` button at the top right has Edit, Find Cover, Add to Collection and Delete Book…. Tapping a book without a cover shows the Find Cover button on the generated cover. A long press on the cover offers Find Cover, `Choose Photo…` / `Foto auswählen…`, `Take Photo…` / `Foto aufnehmen…` and `Remove Cover Image` / `Coverbild entfernen`.

### Add Book and Edit Book

Add Book opens as a full-height sheet on iPhone with `Cancel` / `Abbrechen` and `Add` / `Hinzufügen` at the top. It has the Mac editor's fields and behaviour:

- Complete at the top, with the Mac's grey explanation, status line, amber no-match hint, red unreachable hint with `Try Again` / `Erneut versuchen`, and green banner with `Undo` / `Widerrufen`. Filled fields get the light green fill; differing values get the note with `Use`.
- The cover, with `Choose Photo…` and `Take Photo…`.
- ISBN (with a barcode button on the right, see "Scanning into the ISBN field"), Title, Subtitle, Authors, Year, Pages. Publisher, the two languages and Date Added sit under `More` / `Mehr`.
- The status segments (Want to Read, Reading, Read; tapping the selected one clears it), the dates and rating for the status, and Collections.
- Several editions open "Choose an edition" / "Ausgabe wählen" as a sheet over the editor.

The keyboard's Return moves to the next field. Edit Book is the same sheet with `Save` / `Speichern`.

### Finish Reading and ratings

Finish Reading opens as a half sheet: the book's title, Started, Finished on (today), Rating and Notes, with `Cancel` and `Done` / `Fertig`. A tap on a star gives it whole, a second tap on the same star makes it half; sliding a finger across the stars sets them in half steps. Abandon opens its sheet the same way.

### Undo

Each change is one undo step, as on the Mac. The system gestures undo and redo it: shaking the device, or a three-finger swipe left (undo) and right (redo). iOS names the step ("Undo Add Book"). Delete Book… always asks first.

### Scanning

The Scan Barcode button in the Library screen's bottom bar opens the scanner full screen. On iPad the same button sits in the list's toolbar.

- The rear camera's picture fills the screen, not mirrored. `Cancel` / `Abbrechen` and a torch button (accessibility label "Torch" / "Taschenlampe") sit at the top, the white guide frame in the middle.
- "Point the camera at the barcode on the back of the book." / "Richte die Kamera auf den Barcode auf der Rückseite des Buchs." under the frame.
- The bottom bar shows "Added in this round: 2" / "In dieser Runde: 2" (hidden before the first book) and `Done` / `Fertig`.

On the device every scan is a round; there is no checkbox for it.

**An ISBN is read.** The device gives a short haptic tap and plays the scan sound (silent when the ringer is off). The frame turns green and a card slides up over the lower part of the camera. While the sources are asked, it shows "ISBN 978-3-596-29431-2" and the status line "Searching Deutsche Nationalbibliothek…" for the first source that is on; `Add and Scan Next` is disabled.

**The card**, once a book is found:

- Cover, title, authors, "publisher · year · pages", and the source ("from Deutsche Nationalbibliothek" / "von Deutsche Nationalbibliothek").
- When there are more editions: "3 other editions" / "3 weitere Ausgaben" (plural rules). Tapping it opens "Choose an edition" as a sheet; the chosen edition replaces the card's book.
- The status segments, Want to Read selected for the first book of a round.
- "Collections" / "Sammlungen" with the chosen collections; tapping it opens a picker.
- `Edit…` / `Bearbeiten…` opens Add Book with the card's book, for every field. Adding there continues the round.
- `Add and Scan Next` / `Hinzufügen und nächstes scannen` adds the book (one undo step "Add Book") and the camera looks for the next barcode.

The status and collections chosen for a book are preset for the next one in the round, as on the Mac. A new round starts with Want to Read and no collections.

**No book found.** The card shows the ISBN and "No book found for ISBN 978-3-12-345678-0. Check the number, or enter the title and author instead." / "Kein Buch gefunden für ISBN 978-3-12-345678-0. Prüfe die Nummer oder gib stattdessen Titel und Autor ein." with `Skip` / `Überspringen` (back to the camera) and `Edit…` (Add Book with the ISBN).

**No source reachable.** The card shows "Can't reach any book source" / "Keine Buchquelle erreichbar" with `Try Again` and `Edit…`.

**Not an ISBN.** The frame turns amber and the Mac's hint appears over the picture for 4 seconds: "This barcode isn't an ISBN (4 006381 333931). Look for the one that starts with 978 or 979." The camera keeps looking.

**Already in your library.** The card shows the book's cover, "Already in your library" / "Schon in deiner Bibliothek", its title and year, and its current status ("Finished 2 Mar 2019"). `Show Book` / `Buch zeigen` ends the round and opens the book; `Add Anyway` / `Trotzdem hinzufügen` shows the card for a new book; `Scan Another` / `Nächstes scannen` goes back to the camera.

**Ending a round.** `Done` or `Cancel` closes the scanner and returns to the screen it was opened from. The books added stay. Leaving the app or locking the device pauses the camera; coming back resumes it.

**No camera access.** The first time, iOS asks with "Buchhalter uses the camera to read the barcode on the back of a book." / "Buchhalter verwendet die Kamera, um den Barcode auf der Rückseite eines Buchs zu lesen." When access is denied, the screen shows "Buchhalter can't use the camera" / "Buchhalter kann die Kamera nicht verwenden", "Allow camera access for Buchhalter in Settings." / "Erlaube Buchhalter den Kamerazugriff in den Einstellungen.", `Open Settings` / `Einstellungen öffnen` and `Type ISBN Instead` / `ISBN eingeben` (Add Book with the cursor in the ISBN field). Returning from Settings with access granted starts the camera.

### Scanning into the ISBN field

The barcode button next to the ISBN field in Add Book and Edit Book opens the scanner over the editor, without the card, the round line and `Done`. A read ISBN plays the tap and sound, closes the scanner and replaces the field's value. In Add Book, Complete starts; in Edit Book it does not, as on the Mac.

### Settings

The gear button opens Settings as a sheet with `Done`. It holds the Mac's two tabs as sections of one scrolling list:

- "Book Lookup" / "Buchsuche": the three sources with a checkmark each, in the user's order. `Edit` lets the user drag them. Google Books is greyed with "needs a key" until a key is saved. The Mac's explanation sits under the list. The order and switches are per device, as on the Mac.
- "Google Books": the key row ("Not set", or the masked key). Tapping it opens the Mac's key section: the field, `Save Key` / `Schlüssel sichern` with its check, the messages, `Change…` / `Ändern…` and `Remove` / `Entfernen`, and the help with the steps to get a key.
- "iCloud": Status, Last synced and In iCloud, the problem message with its button, and the Mac's closing note.

### The Google Books key in iCloud Keychain

The key is kept in iCloud Keychain, so it is entered once and every device of the same Apple Account that uses iCloud Keychain has it, the Mac included. The note under the key says: "The key is kept in iCloud Keychain, so you enter it once for all your devices that use it. Removing it removes it everywhere." / "Der Schlüssel liegt im iCloud-Schlüsselbund. Du gibst ihn einmal für alle deine Geräte ein, die ihn nutzen. Wenn du ihn entfernst, ist er überall entfernt."

On the Mac, the key saved before this change moves to iCloud Keychain at the first launch of the new build, without a prompt. When iCloud Keychain is off for the Apple Account, the key stays on the device where it was entered; iOS and macOS do not tell an app whether iCloud Keychain is on, so the app shows no separate message for it.

A key that Google rejects on one device turns the Settings line red on that device; the other devices find out the next time they ask Google Books. `buchhalter-cli` keeps its own copy of the key, as today.

### Sync

The iPhone, the iPad and the Mac share one library. A change on one device appears on the others within seconds to a minute while they are online. Without a connection the app works on what it has and sends the changes when the connection is back. The rules for sync duplicates (authors, collections, list settings) are the Mac's; books are never merged.

### iPad

The iPad runs the same app with the Mac's layout:

- **Landscape:** three columns, always open: the sidebar (Library and Collections, `New Collection` and the gear at the bottom), the list, and the book's detail. Picking a list or a book keeps all three. In grid view, two columns, and opening a book shows its detail with a back button, as on the Mac.
- **Portrait:** it starts with the list of the last list over the dimmed detail; the sidebar button shows the lists. Picking a list closes the sidebar at once and shows its books, without a slide. Tapping a book closes the list too, so only the detail shows. Rotating to landscape opens all columns again.
- Add Book, Edit Book, Settings and the sort levels open as centred sheets, 620 pt wide. Finish Reading and Abandon open as smaller centred sheets.
- The scanner opens full screen, as on the iPhone.
- With a hardware keyboard the Mac's shortcuts work: `⌘N` Add Book, `⇧⌘N` Scan Barcode, `⌘F` Search, `⌘⌫` Delete Book…, `⌘Z` and `⇧⌘Z` Undo and Redo. Holding `⌘` shows them.
- With a pointer, a secondary click opens the long-press menu.

The iPhone and iPad share every rule; only the layout differs.

### Changes on the Mac

- `Start Reading` / `Lesen beginnen` joins the book detail (the prominent button next to `Edit`), the book's right-click menu and the Book menu for a book in Want to Read. It starts a reading dated today, one undo step "Start Reading" / "Lesen beginnen".
- The Google Books key moves to iCloud Keychain (see above). The Settings pane shows the same note.

### Appearance and accessibility

The app follows the system's light and dark mode and Dynamic Type. The deep green accent, the serif titles and the generated cover colours are the Mac's. Every icon-only button has an accessibility label in both languages.

### Languages

The app follows the device's language; the iOS Settings app offers a per-app language under Buchhalter. The Mac's texts keep their German wording. New texts:

| English | German |
|---|---|
| Library (screen title) | Bibliothek |
| Search All Books | Alle Bücher durchsuchen |
| Settings | Einstellungen |
| Start Reading | Lesen beginnen |
| Delete (swipe) | Löschen |
| More | Mehr |
| Choose Photo… | Foto auswählen… |
| Take Photo… | Foto aufnehmen… |
| Downloading your library from iCloud… | Deine Bibliothek wird aus iCloud geladen… |
| Your library is in iCloud | Deine Bibliothek ist in iCloud |
| Open Settings | Einstellungen öffnen |
| 3 other editions | 3 weitere Ausgaben |
| Skip | Überspringen |
| Torch (accessibility) | Taschenlampe |
| Point the camera at the barcode on the back of the book. | Richte die Kamera auf den Barcode auf der Rückseite des Buchs. |
| Allow camera access for Buchhalter in Settings. | Erlaube Buchhalter den Kamerazugriff in den Einstellungen. |

Existing texts used on the device, for reference: Want to Read / Will ich lesen, Reading / Lese ich, Read / Gelesen, Finish Reading… / Fertig gelesen…, Abandon / Lektüre abbrechen, Read Again / Nochmal lesen, Readings / Lektüren, Edit / Bearbeiten, Delete Book… / Buch löschen…, Find Cover / Coverbild suchen, Sort Books / Bücher sortieren, Complete / Vervollständigen, Choose an edition / Ausgabe wählen, Add and Scan Next / Hinzufügen und nächstes scannen, Done / Fertig.

## Goals

- The `make` target installs the app on the user's iPhone; opened there, it shows the same lists, counts and collections as the Mac within a minute.
- A book added on the iPhone appears on the Mac within a minute, and the other way round, with its cover.
- Finishing a book on the iPhone with 4.5 stars shows it under Read on the Mac with the date and the rating.
- Sliding a Want to Read row right and tapping `Start Reading` moves the book to Reading, dated today. Shaking the iPhone offers "Undo Start Reading", which moves it back.
- Scanning five books in a row on the iPhone adds five books with five taps on `Add and Scan Next`; "Added in this round: 5" shows; the status and collection chosen for the first are preset for the others.
- Scanning "Buddenbrooks" (978-3-596-29431-2) when it is already in the library shows "Already in your library"; `Show Book` opens it.
- A scanned ISBN with several editions shows "N other editions"; choosing one replaces the card's book.
- Without camera access, the scanner shows the message and `Open Settings` opens Buchhalter's page in iOS Settings.
- A Google Books key saved on the Mac shows as saved in the iPhone's Settings without typing it again, and Complete on the iPhone uses Google Books. `Remove` on the iPhone removes it on the Mac.
- On iPad in landscape the sidebar, list and detail show side by side; `⌘N` with a keyboard opens Add Book.
- Edit a field in the iPhone's book detail while the Mac shows the same book: the Mac's detail updates without reopening the book.
- With the device set to German, every screen, menu, sheet, card, hint and the camera prompt is in German. The Mac in German shows `Lesen beginnen` in the right-click menu:

```
open build/Buchhalter.app --args -AppleLanguages '(de)'
```

## Non-goals

- TestFlight and the App Store.
- Widgets, Shortcuts and Siri, a share extension, Live Activities.
- Several windows side by side on iPad, Stage Manager features beyond one window, drag and drop of books between apps, Apple Pencil.
- Landscape on iPhone.
- Apple Watch and Vision Pro.
- `buchhalter-cli` on iOS.
- The assistant.
- Importing from a file or another app.
- Scanning from a photo, reading the ISBN from the copyright page, barcodes other than EAN-13 ISBNs (as on the Mac).
- A USB or Bluetooth barcode scanner on iPad beyond typing into the ISBN field.
