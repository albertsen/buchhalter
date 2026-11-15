# Book Lookup

`Complete` / `Vervollständigen` in Add Book and Edit Book looks up a book's data and cover in the Deutsche Nationalbibliothek, with Open Library as a fallback, from a title and author or from an ISBN.

Design: https://claude.ai/artifact/KWjhfRAqkfyM8d4sYB3ggT (section "Book Lookup")

## Problem

1. Every book is typed in by hand: subtitle, year, pages, publisher, ISBN. For a book on the shelf, that means about ten fields copied from the imprint page.
2. A cover has to be found on the web, saved and dropped onto the sheet. Most books in the library show the generated cover because this takes too long.
3. Values typed from memory are often wrong, such as the year of the first edition instead of this edition, or a page count from a different printing.

## Experience

### The Complete button

Add Book and Edit Book have a `Complete` button (German `Vervollständigen`) at the top right of the sheet header, next to the sheet title. It has a magnifier icon and a green outline. Under the sheet title is one grey line:

- "Type a title and author, or an ISBN. Complete looks up the rest in the Deutsche Nationalbibliothek, including the cover."
- "Gib einen Titel und Autor oder eine ISBN ein. Vervollständigen sucht den Rest in der Deutschen Nationalbibliothek, auch das Cover."

The rest of the sheet is unchanged.

`Complete` is enabled when the sheet has a title and at least one author, or a valid ISBN. Otherwise it is disabled, and its tooltip says "Enter a title and author, or an ISBN" / "Gib einen Titel und Autor oder eine ISBN ein". With a valid ISBN, Complete searches by ISBN. Without one, it searches by title and author. An invalid ISBN is ignored for the search and keeps its red border.

Nothing is looked up while the user types. The lookup runs only when the user clicks `Complete`.

### Where the data comes from

Complete asks the Deutsche Nationalbibliothek first. It holds every book published in Germany, including new and small-press books. Open Library (mostly English books) is asked only when the Deutsche Nationalbibliothek finds nothing. Neither service needs an account or a key.

Only printed books are matches, in any language and including translations. Audiobooks, e-books and CDs are never shown.

### Looking up

While the lookup runs:

- The button reads "Looking up…" / "Wird gesucht…" with a spinner, and is disabled.
- A `Stop` / `Stopp` button sits next to it.
- A line under the header says "Searching the Deutsche Nationalbibliothek for "Buddenbrooks" by Thomas Mann…" / "Suche in der Deutschen Nationalbibliothek nach „Buddenbrooks“ von Thomas Mann…". For an ISBN it reads "…for ISBN 978-3-15-011537-4…" / "…nach ISBN 978-3-15-011537-4…". When Open Library is asked, the line names Open Library.

The lookup never blocks the sheet. All fields stay editable, and `Add Book` / `Save` still work. `Stop` ends the lookup and changes nothing. Adding or saving the book, or `Cancel`, also ends the lookup. A book added during the lookup is added with the values the user entered.

### One match

When exactly one book matches, or the ISBN matches one book, Complete fills in the sheet at once without asking.

### Several matches

When several books match, a sheet "Choose an edition" / "Ausgabe wählen" opens over Add Book or Edit Book. Under the title: "12 books match "Buddenbrooks" by Thomas Mann. Newest first." / "12 Bücher passen zu „Buddenbrooks“ von Thomas Mann. Neueste zuerst."

Each row shows:

- A small cover. A record without a cover shows the generated cover.
- The title in the serif.
- "Thomas Mann · Reclam · 2026": authors, publisher, year.
- "781 pages · German · ISBN 978-3-15-011537-4" / "781 Seiten · Deutsch · ISBN 978-3-15-011537-4".

The newest edition is at the top and is selected. The selected row is drawn in the accent green. The arrow keys move the selection.

The footer says "Double-click a row to use it." / "Doppelklicke eine Zeile, um sie zu übernehmen." and has `Cancel` / `Abbrechen` and `Use This Edition` / `Diese Ausgabe übernehmen` (the primary button, also `Return`). Double-clicking a row has the same effect as `Use This Edition`. `Cancel` and `Esc` close the sheet and change nothing.

### What gets filled in

Complete fills these fields: subtitle, authors, year, pages, language, original language, publisher, ISBN and cover.

- Year is the year of this edition, the one the library stores, not the year of first publication.
- Original Language is filled only when the record names one, which is the case for a translation.
- A language the Language popups do not offer leaves the field alone.
- The ISBN is written in one form everywhere: ISBN-13 with hyphens where the International ISBN Agency places them ("978-0-306-40615-7", "978-3-15-011537-4"). Filled-in and typed ISBNs take this form, a typed one when the user leaves the field.
- Authors that are new to the library get the usual "Sorted as" guess, which the user can correct with `Edit` as before. An author already in the library is reused with its sort name.

Complete never touches Status, the reading dates, rating, notes or Collections.

The sheet never scrolls. The banner, hints and notes make it taller, so every field stays in view.

### The user's values win

Add Book and Edit Book follow the same rule:

- An empty field is filled.
- A field with the same value stays as it is.
- A field whose value differs keeps the user's value. A small note under the field offers the found value: "DNB: 2009 · Use" / "DNB: 2009 · Übernehmen". With Open Library as the source, the note reads "Open Library: 2009 · Use". Clicking `Use` / `Übernehmen` puts the value in the field and removes the note.
- The title the user typed is never replaced. A differing title is offered the same way.
- The cover is filled only when the book has no image of its own. Otherwise, when the record has a cover, the offer "Use DNB cover" / "DNB-Cover übernehmen" (or "Use Open Library cover" / "Open-Library-Cover übernehmen") appears next to the cover.

Example in Edit Book, in German, for "Piercing" by Ryu Murakami. Untertitel "Roman", Verlag "Liebeskind", Originalsprache "Japanisch" and the cover are filled. Jahr keeps 1994 and shows "DNB: 2009 · Übernehmen". Seiten keeps 176 and shows "DNB: 173 · Übernehmen".

### After filling

Each field Complete filled has a light green background and a green border. A filled cover has a green outline. A field loses its highlight when the user edits it.

A green banner under the header names the result and the source:

- "Filled in 6 fields from the Deutsche Nationalbibliothek. Check them, then add the book." / "6 Felder aus der Deutschen Nationalbibliothek ergänzt. Prüfe sie, dann füge das Buch hinzu."
- With differing values: "Filled in 4 empty fields from the Deutsche Nationalbibliothek. 2 values differ and stay until you use them." / "4 leere Felder aus der Deutschen Nationalbibliothek ergänzt. 2 Angaben weichen ab und bleiben, bis du sie übernimmst."
- With Open Library: "…from Open Library." / "…aus Open Library …".
- When everything already matches: "Nothing to fill in. Everything matches the Deutsche Nationalbibliothek." / "Nichts zu ergänzen. Alles stimmt mit der Deutschen Nationalbibliothek überein."

The counts use the catalog's plural rules ("1 field" / "1 Feld").

`Undo` / `Widerrufen` in the banner puts every field Complete filled or the user took with `Use` back to its value before Complete. It also removes the highlights, the notes and the banner. Clicking `Complete` again starts a new lookup and replaces the banner and notes.

Nothing is saved until `Add Book` or `Save` / `Speichern`. `Cancel` discards everything, including a downloaded cover. Saving is one undo step as before: `⌘Z` after saving reverts the whole change.

The duplicate check covers filled-in data the same way as typed data. When a filled-in ISBN matches a book in the library, the sheet shows "Already in your library: …" with `Show Book` and `Add Anyway`.

### Covers

A cover from the lookup is downloaded once and stored with the book like a dropped image. The library shows it offline, and it syncs with the book later. It can be removed or replaced like any other cover image.

A record without a cover leaves the generated cover. This is normal and shows no message.

### No match

When neither service finds a book, an amber hint appears under the header:

- "No book found for "Buddenbroks" by Thomas Mann. Check the spelling, or enter the ISBN and try again." / "Kein Buch gefunden für „Buddenbroks“ von Thomas Mann. Prüfe die Schreibweise oder gib die ISBN ein und versuche es noch einmal."
- For an ISBN: "No book found for ISBN 978-3-15-011537-4. Check the number, or enter the title and author instead." / "Kein Buch gefunden für ISBN 978-3-15-011537-4. Prüfe die Nummer oder gib stattdessen Titel und Autor ein."

No field changes.

### Service not reachable

When the Deutsche Nationalbibliothek cannot be reached (no internet connection, timeout, server error), a red hint appears with `Try Again` / `Erneut versuchen`:

- "Can't reach the Deutsche Nationalbibliothek. Check the internet connection. You can still add the book by hand." / "Die Deutsche Nationalbibliothek ist nicht erreichbar. Prüfe die Internetverbindung. Du kannst das Buch trotzdem von Hand eintragen."

The same message names Open Library when that service fails. No field changes.

Hints go away when the user changes the title, the authors or the ISBN, or clicks `Complete` again. Adding a book by hand always works, with or without network.

### Languages

| English | German |
|---|---|
| Complete | Vervollständigen |
| Looking up… | Wird gesucht… |
| Stop | Stopp |
| Choose an edition | Ausgabe wählen |
| Use This Edition | Diese Ausgabe übernehmen |
| Cancel | Abbrechen |
| Use | Übernehmen |
| Use DNB cover | DNB-Cover übernehmen |
| Undo | Widerrufen |
| Try Again | Erneut versuchen |
| Save | Speichern |
| Edit Book | Buch bearbeiten |

The source names "Deutsche Nationalbibliothek", "DNB" and "Open Library" are not translated. German grammar inflects the name where needed ("aus der Deutschen Nationalbibliothek").

## Goals

- Add Book and Edit Book show `Complete` / `Vervollständigen` at the top right and the explanatory line under the title.
- `Complete` is disabled with the tooltip "Enter a title and author, or an ISBN" until a title and an author, or a valid ISBN, are entered. Typing alone never starts a lookup.
- "Buddenbrooks" with "Thomas Mann" opens "Choose an edition" with the newest edition first. `Use This Edition` and double-click fill the sheet. `Cancel` changes nothing.
- The ISBN of a single edition fills the sheet without the edition sheet.
- After filling, the filled fields are green, and the banner names the number of fields and the source. `Undo` restores every field to its state before Complete.
- In Edit Book, empty fields are filled, and differing values keep the user's value with "DNB: <value> · Use". Clicking `Use` takes the value. The title is never replaced. A book with its own cover keeps it and shows "Use DNB cover".
- Status, readings and collections never change through Complete.
- A book the Deutsche Nationalbibliothek does not hold but Open Library does is filled from Open Library, and the banner says "from Open Library".
- Audiobooks, e-books and CDs never appear as matches.
- During the lookup, the sheet stays editable, `Stop` ends the lookup without changes, and `Add Book` works.
- A misspelt title shows the amber no-match hint. With the network off, the red hint with `Try Again` appears, and the book can still be added by hand.
- A cover from the lookup is still shown after relaunching with the network off.
- A filled-in ISBN that is already in the library shows "Already in your library: …".
- Saving after Complete is one step for `⌘Z`.
- The sheet does not scroll, also with a banner, hints and notes shown.
- Every ISBN reads "978-…" with hyphens in the right places, in the sheet and in the book's details, also for books added before.
- Started with `-AppleLanguages '(de)'`, the button, line, banner, hints, notes and the edition sheet are in German:

```
open build/Buchhalter.app --args -AppleLanguages '(de)'
```

## Non-goals

- Barcode scanning.
- Suggestions while typing.
- Refreshing many books at once.
- Google Books or other sources.
- The year of first publication.
- Editing lookup results in the match list.
- The AI assistant.
