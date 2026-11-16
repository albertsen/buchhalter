# Barcode Scanning

The user adds a book by holding the barcode on its back up to a camera: Buchhalter reads the ISBN, looks the book up and opens Add Book with the result, on the Mac now and on iPhone and iPad later.

Design: https://claude.ai/artifact/KWjhfRAqkfyM8d4sYB3ggT (section "Barcode Scanning")

## Problem

1. Adding a book with Complete means typing its 13-digit ISBN or its title and author. For a shelf of books this is slow, and a mistyped digit gives an invalid ISBN or the wrong book.
2. The barcode on the back of almost every book since the 1980s is its ISBN-13 (EAN-13, starting with 978 or 979). Buchhalter cannot read it.
3. The iPhone and iPad app comes later and will scan with the device's camera. The Mac needs the same flow now, so both apps add books the same way.

## Experience

### Opening the scanner

On the Mac there are three ways:

- `File → Scan Barcode…` / `Ablage → Barcode scannen…` (`⇧⌘N`), right below `Add Book…` / `Buch hinzufügen…` (`⌘N`).
- A barcode button in the toolbar, next to the `+` button. Its tooltip and accessibility label: "Scan Barcode" / "Barcode scannen".
- A barcode button right of the ISBN field in Add Book and Edit Book (see "Scanning into an open Add Book").

The first two open the sheet `Scan Barcode` / `Barcode scannen` over the main window.

### The scan sheet

The sheet is 560 pt wide. From top to bottom:

- The title, and on the right `Camera` / `Kamera` with a menu of the cameras the Mac has: the built-in camera ("FaceTime HD Camera"), an iPhone nearby (Continuity Camera), USB cameras. The names come from macOS.
- A grey line: "Hold the barcode on the back of the book up to the camera. Buchhalter reads the ISBN and looks up the book." / "Halte den Barcode auf der Rückseite des Buchs vor die Kamera. Buchhalter liest die ISBN und sucht das Buch."
- The live camera picture, 330 pt high, with a white guide frame in the middle and the status "Looking for a barcode…" / "Suche nach einem Barcode…" at the bottom.
- A small tip: "Tip: an iPhone near this Mac can be the camera (Continuity Camera). A USB barcode scanner works too: scan into the ISBN field of Add Book." / "Tipp: Ein iPhone in der Nähe dieses Macs kann die Kamera sein (Integration der Kamera). Ein USB-Barcodescanner geht auch: Scanne in das ISBN-Feld von „Buch hinzufügen“."
- The footer: the checkbox `Scan several books in a row` / `Mehrere Bücher nacheinander scannen`, then `Type ISBN Instead` / `ISBN eingeben`, and `Cancel` / `Abbrechen` (also `Esc`).

The first time, the camera menu picks an iPhone if one is available, because its camera focuses close up and reads barcodes reliably; otherwise the built-in camera. After that the last choice is kept on this Mac. Changing the camera switches the picture at once. When the chosen camera disappears (the iPhone moves away), the menu falls back to the built-in camera.

The built-in camera of a Mac has a fixed focus. Held too close, the barcode is blurry; at about 30 to 40 cm it is often readable. Buchhalter offers it, but makes no promise that it reads every barcode with every Mac. The iPhone, typing and a USB scanner are the reliable ways.

`Type ISBN Instead` closes the scan sheet and opens Add Book with the cursor in the ISBN field.

The camera runs only while the sheet is open. The camera picture is never stored and never leaves the Mac. Only the ISBN read from it is used.

### The picture is a mirror

The picture is mirrored, as in FaceTime and Photo Booth, for every camera: moving the book to the left moves it to the left on the screen, so the barcode is easy to put into the frame. The digits printed on the book appear reversed in the picture, as in FaceTime.

Only the picture is mirrored. The barcode is read from the camera's unmirrored image. The green frame sits on the barcode where it appears in the mirrored picture. The status texts and the ISBN shown over the picture read normally.

### An ISBN is read

When the camera sees an EAN-13 barcode that starts with 978 or 979 and has a valid check digit:

- A short sound plays.
- The frame turns green, and the status reads the ISBN, hyphenated: "ISBN 978-3-596-29431-2".
- After half a second, Add Book opens over the scan sheet, with the ISBN filled in and highlighted, and Complete starts at once. The status line reads "Searching Deutsche Nationalbibliothek for ISBN 978-3-596-29431-2…" for the first source that is on, as Complete does today.

From here, Add Book works as today: several editions open "Choose an edition"; no match shows the amber hint; no source reachable shows the red hint. The book can always be finished by hand. A 5-digit price add-on printed next to the barcode is ignored.

The scan sheet stays open under Add Book, greyed, and its camera pauses.

### A barcode that isn't an ISBN

Other barcodes on a book (an EAN-13 that does not start with 978 or 979, such as a price or a German retail code) are not used. The frame turns amber, and a hint over the picture reads:

- "This barcode isn't an ISBN (4 006381 333931). Look for the one that starts with 978 or 979."
- "Dieser Barcode ist keine ISBN (4 006381 333931). Such den, der mit 978 oder 979 beginnt."

The camera keeps looking. The hint goes away after 4 seconds or when the next barcode is read. QR codes and other barcode types are ignored without a hint.

### Already in your library

When the ISBN belongs to a book already in the library, Add Book does not open. The scan sheet shows a banner under the picture:

- "Already in your library: Buddenbrooks (1901)" / "Schon in deiner Bibliothek: Buddenbrooks (1901)", the same label as in Add Book's duplicate banner
- `Show Book` / `Buch zeigen` closes the scan sheet (ending a round) and selects the book.
- `Add Anyway` / `Trotzdem hinzufügen` opens Add Book with the ISBN, as for a new book. Add Book shows its own duplicate banner and accepts `Add Anyway` there too.
- `Scan Another` / `Nächstes scannen` (the primary button) clears the banner and the camera looks again.

### No camera

When macOS has not allowed Buchhalter to use the camera, the picture area shows:

- "Buchhalter can't use the camera" / "Buchhalter kann die Kamera nicht verwenden"
- "Allow camera access for Buchhalter in System Settings → Privacy & Security → Camera." / "Erlaube Buchhalter den Kamerazugriff unter Systemeinstellungen → Datenschutz & Sicherheit → Kamera."
- `Open System Settings…` / `Systemeinstellungen öffnen…`, which opens that page.

The first time the scanner opens, macOS asks for camera access with the text "Buchhalter uses the camera to read the barcode on the back of a book." / "Buchhalter verwendet die Kamera, um den Barcode auf der Rückseite eines Buchs zu lesen."

When the Mac has no camera at all:

- "No camera found" / "Keine Kamera gefunden"
- "Connect a camera or put an iPhone near this Mac. You can also type the ISBN." / "Schließ eine Kamera an oder leg ein iPhone in die Nähe dieses Macs. Du kannst die ISBN auch eingeben."

When access is granted or a camera appears while the sheet is open, the picture starts without reopening the sheet.

### One book

With `Scan several books in a row` off, Add Book's buttons are `Cancel` and `Add Book` as today:

- `Add Book` adds the book, closes Add Book and the scan sheet, and selects the new book.
- `Cancel` closes Add Book and goes back to the camera, which starts looking again.

### Several books in a row

With `Scan several books in a row` on:

- Add Book's main button reads `Add and Scan Next` / `Hinzufügen und nächstes scannen` (also `Return`). It adds the book, closes Add Book, and the camera looks for the next barcode.
- Add Book's footer shows "Added in this round: 2" / "In dieser Runde: 2" (plural rules; hidden before the first book).
- The status and the collections chosen for a book in the round are preset for the next book. Changing them changes the preset for the books after it.
- `Cancel` in Add Book skips this book and goes back to the camera.
- `Cancel` in the scan sheet ends the round and closes it. The books added stay; the last one added is selected.

The checkbox is kept on this Mac. A new round (opening the scanner again) starts with Add Book's usual defaults: status Want to Read, no collections.

Each added book is its own undo step "Add Book", as today.

### Scanning into an open Add Book

The barcode button next to the ISBN field opens the scan sheet over Add Book or Edit Book. The checkbox and the footer buttons other than `Cancel` are hidden. When an ISBN is read, the sound plays, the scan sheet closes, the ISBN replaces the field's value, and in Add Book Complete starts. In Edit Book the ISBN is only filled in; Complete starts when the user clicks it, as today. A barcode that is not an ISBN shows the amber hint, and the duplicate banner does not appear here (Add Book shows its own).

### A USB barcode scanner

A USB or Bluetooth barcode scanner types the digits and `Return` like a keyboard. Scanned into the ISBN field of Add Book, it fills the field; `Return` then saves the book as today. Nothing else is needed for it.

### iPhone and iPad (direction for the iOS app)

The design shows where the iOS app goes; it is built with the iOS app, not in this spec:

- `Scan Barcode` opens a full-screen camera with `Cancel` and a torch button at the top, the guide frame in the middle, and "Point the camera at the barcode on the back of the book." / "Richte die Kamera auf den Barcode auf der Rückseite des Buchs."
- The rear camera is not mirrored.
- A read ISBN looks the book up and shows a card over the camera: cover, title, author, publisher, year, pages, the source ("from Deutsche Nationalbibliothek"), the status choice, and `Edit…` / `Bearbeiten…` and `Add and Scan Next` / `Hinzufügen und nächstes scannen`. `Edit…` opens the full editor.
- The bottom bar shows "Added in this round: 2" and `Done` / `Fertig`.
- The rules for non-ISBN barcodes, duplicates, presets in a round and camera access are the same as on the Mac.

On the Mac every scanned book goes through Add Book; the card is for the phone's small screen only.

### Languages

| English | German |
|---|---|
| Scan Barcode… (menu) | Barcode scannen… |
| Scan Barcode (sheet title, button) | Barcode scannen |
| Camera | Kamera |
| Looking for a barcode… | Suche nach einem Barcode… |
| Scan several books in a row | Mehrere Bücher nacheinander scannen |
| Type ISBN Instead | ISBN eingeben |
| Cancel | Abbrechen |
| Add and Scan Next | Hinzufügen und nächstes scannen |
| Added in this round: 2 | In dieser Runde: 2 |
| Already in your library: … | Schon in deiner Bibliothek: … |
| Show Book | Buch zeigen |
| Add Anyway | Trotzdem hinzufügen |
| Scan Another | Nächstes scannen |
| Buchhalter can't use the camera | Buchhalter kann die Kamera nicht verwenden |
| No camera found | Keine Kamera gefunden |
| Open System Settings… | Systemeinstellungen öffnen… |
| Edit… (iPhone) | Bearbeiten… |
| Done (iPhone) | Fertig |

"Continuity Camera" is "Integration der Kamera" in German macOS. Camera names come from the system.

## Goals

- `⇧⌘N`, `File → Scan Barcode…` and the toolbar button open the scan sheet with the live picture.
- The picture is mirrored like FaceTime: the book moves to the same side as the hand. The ISBN shown over the picture reads normally.
- Holding the back of "Buddenbrooks" (ISBN 978-3-596-29431-2) up to an iPhone used as the camera plays a sound, shows "ISBN 978-3-596-29431-2" on a green frame, and opens Add Book with the ISBN and Complete running.
- With the built-in camera of a Mac, the same barcode at 30 to 40 cm is read on a Mac with a 1080p camera.
- A non-ISBN barcode shows the amber hint for 4 seconds and opens nothing.
- Scanning a book already in the library shows "Already in your library: …" with `Show Book`, `Add Anyway` and `Scan Another`. `Show Book` selects it.
- With the checkbox on, five books scanned in a row are added with five `Add and Scan Next` clicks; the count reads "Added in this round: 5"; the status and collection chosen for the first are preset for the others.
- `Cancel` in Add Book goes back to the camera; `Cancel` in the scan sheet ends the round.
- With the checkbox off, `Add Book` closes both sheets and selects the new book.
- The barcode button next to the ISBN field in Add Book fills the field from a scan and starts Complete.
- Without camera access, the sheet shows the message and `Open System Settings…` opens the camera privacy page. Granting access starts the picture without reopening the sheet.
- The camera's light goes off when the scan sheet closes.
- A USB barcode scanner, scanning into the ISBN field, fills it.
- Started in German, the menu item, the sheet, all hints, the banner, the buttons and the camera access prompt are in German:

```
open build/Buchhalter.app --args -AppleLanguages '(de)'
```

## Non-goals

- The iPhone and iPad app itself. The design and the section above are its direction.
- Barcodes other than EAN-13 ISBNs: QR codes, ISBN-10 barcodes, UPC codes of US mass-market paperbacks.
- Reading the ISBN from the copyright page by text recognition.
- Scanning from a photo or an image file.
- A switch for the sound.
- A switch for mirroring the picture, for example for a document camera pointing down at the desk.
- Adding a book on the Mac without Add Book (the iPhone's card).
- Scanning the cover image to find a book.
