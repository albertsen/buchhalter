# Library

Buchhalter lets the user add books by hand, see them in the sidebar lists and in their own collections, sort and search them, and track each reading from Want to Read to finished, in English and German.

Design: https://claude.ai/artifact/KWjhfRAqkfyM8d4sYB3ggT

## Experience

### The window

Buchhalter opens one native macOS window with three columns: sidebar, book list, detail pane. The interface uses the system font. Book titles use the serif New York. One accent colour, a deep green, marks the selection, the primary button and the rating stars.

The sidebar has two sections:

- `Library` (`Bibliothek`) with four lists, each with an icon and a count: `Reading` (`Lese ich`), `Want to Read` (`Will ich lesen`), `Read` (`Gelesen`), `All Books` (`Alle Bücher`).
- `Collections` (`Sammlungen`) with the user's collections and their counts, for example Read in 2026, Classics to Read, Owned, Lent out. `New Collection` (`Neue Sammlung`) sits at the bottom of the sidebar.

The lists hold these books:

- Reading: books with an open reading.
- Want to Read: books marked Want to Read.
- Read: books whose latest reading is finished.
- All Books: every book, abandoned ones included.

Counts update as soon as a book is added, changed or deleted.

The toolbar over the list and detail pane shows the list's name and its book count ("1 book", "2 books" / "1 Buch", "2 Bücher"), a Sort button that names the current order ("Sort: Author, Year" / "Sortieren: Autor, Jahr"), a List/Grid switch, a search field (`Search` / `Suchen`) and a `+` button (Add Book).

In list view, each row shows a small cover, the title in the serif, the author, and a status line: "Started 3 Oct 2026" for a book being read, "Finished 2 Mar 2019" for a read book, "Abandoned 5 Nov 2026" for an abandoned one. The selected row is drawn in the accent colour.

In grid view, the covers sit in a grid (six columns at the design's window width). Each cover has the title, the author and the rating stars below it, or "No rating" if the book has none. Each list and each collection remembers whether it shows a list or a grid.

### Empty library

On first launch, All Books is selected and the toolbar shows "No books". The four lists show a count of 0. The Collections section is empty and shows the hint "Group books your way, like "Read in 2026".". The centre of the window shows:

- "Your library is empty"
- "Add the book you are reading now, or the ones you want to read next."
- an `Add Book…` button
- "or press ⌘N"

### Adding a book

`⌘N`, the toolbar `+` button and `Add Book…` open the Add Book sheet, attached to the window. Fields from top to bottom:

- Title.
- Subtitle (optional).
- Authors as chips, with an "Add author" field. Under it: "Sorted as: Mann, Thomas" with an `Edit` button (see Authors and sorting names).
- Year, Pages.
- Language and Original Language / Originalsprache, two popups. Original Language is for a translation and is optional (`None`). When it is the same as Language, it is not stored.
- Publisher (optional).
- ISBN (optional).
- Cover: the cover next to a drop area, "Drop an image here or paste it", with `Choose File…`.
- A divider.
- Status, a segmented control: `Want to Read` / `Reading` / `Read` (German `Will ich lesen` / `Lese ich` / `Gelesen`). Status is optional: clicking the selected segment again clears it, and its tooltip says "Click again to remove the status." / "Zum Entfernen des Status erneut klicken." A new book starts on Want to Read.
- Collections as removable chips, plus `+ Add`.
- `Cancel` and `Add Book`.

The Status control decides what else the sheet asks for:

- No status selected: nothing more. The book has no reading and appears only in All Books and its collections.
- Want to Read: nothing more.
- Reading: Started, a date that defaults to today.
- Read: Started (optional), Finished (defaults to today), Rating (optional, 1–5 stars) and Notes (optional). These fields appear inline in the sheet.

A book can have one or more authors, or none. The year is a year only, not a full date.

The ISBN field accepts ISBN-10 and ISBN-13, with or without hyphens or spaces. The checksum is checked as the user types. An invalid ISBN gives the field a red border and the message "This ISBN is not valid. Check the last digit." `Add Book` stays disabled until the ISBN is valid or empty.

When the ISBN matches a book already in the library, or the title matches together with one of its authors, the sheet shows "Already in your library: Der Zauberberg (1924)" with `Show Book` and `Add Anyway`. `Show Book` closes the sheet and selects the existing book. `Add Anyway` adds the new book, for example a different edition.

`Cancel` closes the sheet and adds nothing.

### Authors and sorting names

Every author has a "Sorted as" name. Buchhalter guesses it the first time the author is typed: the last word is the surname ("Thomas Mann" becomes "Mann, Thomas"). Particles such as von, van and de are left out of the sort key ("Johann Wolfgang von Goethe" becomes "Goethe, Johann Wolfgang von").

`Edit` next to "Sorted as" lets the user fix names the guess gets wrong, for example "García Márquez, Gabriel", "Le Guin, Ursula K.", "Mo Yan" or "Homer". Each author has one sort name, so a correction applies to all of that author's books.

### Covers

A book without a cover image gets a generated cover: a solid colour with the title and author set in the serif. Each book always gets the same colour.

The user adds a cover image in Add Book or Edit Book by dropping an image file on the drop area, pasting an image, or using `Choose File…`. The user can also drop an image onto the large cover in the detail pane. The image can be removed again, and the book then shows its generated cover.

### The detail pane

The detail pane shows the selected book:

- A large cover.
- Title, subtitle, author.
- One line with year · pages · language · ISBN, for example "1901 · 759 pages · German" / "1901 · 759 Seiten · Deutsch". A translation names its original: "1994 · 176 pages · German (original: Japanese)" / "1994 · 176 Seiten · Deutsch (Original: Japanisch)".
- A status badge, for example "Reading since 3 Oct 2026" / "Lese ich seit 3. Okt. 2026". An abandoned book shows "Abandoned" / "Nicht zu Ende gelesen".
- Buttons that depend on the status:
  - Reading: `Finish Reading…` (`Fertig gelesen…`, the primary button), `Abandon` (`Lektüre abbrechen`), `Edit` (`Bearbeiten`).
  - Finished or abandoned: `Read Again`, `Edit`.
  - Want to Read: `Edit`.
- A Collections row with a chip for each collection the book is in, and `+ Add to Collection` (`+ Zu Sammlung hinzufügen`).
- A Readings section (`Lektüren`) that lists every reading of the book, newest first. The current one reads "Reading · Started 3 Oct 2026" / "Begonnen am 3. Okt. 2026". Earlier ones read "Finished · 12 Jan – 2 Mar 2019" / "12. Jan. – 2. März 2019", with their stars and notes.

`Edit` opens the Add Book sheet as "Edit Book", with every field filled in, and `Save` in place of `Add Book`. The ISBN check and the duplicate check work the same way as in Add Book. An invalid ISBN disables `Save`. Changing Status from Want to Read to Reading here starts a reading. Clearing the status removes the current reading, whether Want to Read, Reading or Read, with its dates, rating and notes. Earlier readings stay, so a reread book goes back to its earlier finished reading. ⌘Z brings the removed reading back. A book whose current reading is abandoned shows no status selected, and saving leaves that reading alone.

### Readings

A reading is one read-through of a book. A book read twice has two readings. A book is never added twice for a reread.

`Finish Reading…` opens the Finish Reading sheet. It shows the title "Finish Reading" with the book's title and author, and these fields:

- Started: shown, read-only.
- Finished: a date, default today.
- Rating: 1–5 stars, with `Clear`.
- Notes: multi-line.
- `Cancel` and `Finish`.

Only the finish date is required. The book moves from Reading to Read.

`Abandon` opens a small sheet with an optional date (default today), an optional note, `Cancel`, and `Abandon`. There is no confirmation dialog. In German the sheet's buttons are `Abbrechen` (Cancel) and `Lektüre abbrechen`, because "Abbrechen" is already the German Cancel. An abandoned book leaves Reading. From then on it appears only in All Books and in its collections, with the "Abandoned" / "Nicht zu Ende gelesen" badge.

`Read Again` on a finished or abandoned book starts a new reading with status Reading and Started set to today. The book moves to Reading. Its earlier readings stay in the Readings section.

Double-clicking a reading in the Readings section opens it for editing: its dates, rating and notes, with `Cancel`, `Save` and `Delete Reading`.

Rating and notes are optional everywhere: in Finish Reading, in Add Book with status Read, in Abandon, and when editing a reading. A rating is 1 to 5 whole stars and can be cleared.

### Collections

`New Collection` adds a row to the sidebar with its name field ready for typing. An empty name is not accepted. Names are unique. A name that is already taken shows an error at the field, and the collection is not created under that name.

Right-clicking a collection in the sidebar shows:

- `Rename`.
- `Delete Collection…`, which asks for confirmation. Deleting a collection never deletes its books.

Collections can be dragged into a new order in the sidebar. Books can be dragged from the list or grid onto a collection to add them to it. A book can be in any number of collections, in any status.

There are three more ways to add a book to a collection:

- The Collections chips in Add Book and Edit Book.
- `+ Add to Collection` in the detail pane.
- The book's `Add to Collection` menu.

Right-clicking a book in the list or grid shows:

- `Open`.
- `Add to Collection ›`: a submenu of all collections, with a tick next to each one the book is already in. Choosing a ticked collection removes the book from it. The submenu ends with `New Collection…`.
- `Remove from "Read in 2026"`, shown only when the current list is a collection.
- `Delete Book…`.

### Sorting

Every list and every collection has its own sort order and remembers it between launches. The default for every list is Author A to Z, then Year Published oldest first.

The Sort button in the toolbar opens a popover with:

- The title "Sort" followed by the list's name, for example "Sort Reading".
- `Reset to Default`, which restores the default order.
- One row per level: "Sort by [Author] [A to Z]", then "then by [Year Published] [Oldest first]". Each level has a remove (−) button. The first level cannot be removed.
- `+ Add Level`.
- A footnote that lists the fields and says that books that match on every level are sorted by title.

The fields and how each one names its two directions:

| Field | Directions |
|---|---|
| Author, Title | A to Z / Z to A |
| Year Published, Date Added, Date Started, Date Finished | Oldest first / Newest first |
| Rating, Pages | Lowest first / Highest first |

Rules:

- Author sorts by the first author's sort name. Books without an author come last.
- Books with no value for a date or number field come last, in either direction.
- Comparison ignores case and accents and follows German collation: Ä sorts with A.
- Title sorting ignores a leading article: Der, Die, Das, The, A, An.
- Books that match on every level are sorted by title.
- The toolbar button names the current levels, for example "Sort: Author, Year".

A collection sorted by Author, for example Read in 2026 with 11 books in grid view, shows Eliot, Fontane, Grass, Hesse, Johnson, Mann, Nabokov, Sebald, Tolstoy, Williams, Woolf in that order.

### Search

The search field filters the current list as the user types. It matches title, subtitle, authors, publisher, ISBN and notes, and ignores case and accents: "boll" finds Böll. `⌘F` puts the cursor in the field. `Esc` clears it. When nothing matches, the list shows "No books match "…"" with the search text.

### Undo and deleting

`Delete Book…` is in the book menu and in the book's right-click menu. Pressing `⌫` with a book selected does the same. It asks for confirmation, then removes the book with all its readings.

`⌘Z` undoes every change, and `⇧⌘Z` redoes it. This covers adding, editing, finishing, abandoning, rereading and deleting books, editing and deleting readings, and every collection change (create, rename, reorder, delete, add a book, remove a book).

### Keys

| Key | Action |
|---|---|
| `⌘N` | Add Book |
| `⌘F` | Focus the search field |
| `Esc` (in search) | Clear the search |
| `⌫` | Delete Book… (with confirmation) |
| `⌘Z` / `⇧⌘Z` | Undo / Redo |

### Languages

The whole UI exists in English and German and follows the system language. The user can also set Buchhalter's own language in System Settings. Dates and numbers follow the language: "3 Oct 2026" / "3. Okt. 2026", "759 pages" / "759 Seiten", "1 book" / "1 Buch", "2 books" / "2 Bücher". The user's book data (titles, authors, notes, collection names) is never translated.

| English | German |
|---|---|
| Library | Bibliothek |
| Reading | Lese ich |
| Want to Read | Will ich lesen |
| Read | Gelesen |
| All Books | Alle Bücher |
| Collections | Sammlungen |
| New Collection | Neue Sammlung |
| Readings | Lektüren |
| Finish Reading… | Fertig gelesen… |
| Abandon | Lektüre abbrechen |
| Abandoned | Nicht zu Ende gelesen |
| Edit | Bearbeiten |
| Add to Collection | Zu Sammlung hinzufügen |
| Sort | Sortieren |
| Search | Suchen |

To check German, start the app with:

```
open build/Buchhalter.app --args -AppleLanguages '(de)'
```

## Goals

- `make app` builds `build/Buchhalter.app`, and `open build/Buchhalter.app` starts it.
- `swift test` runs the unit tests.
- On first launch, the empty library screen appears with "Your library is empty", `Add Book…` and "or press ⌘N". The Collections section shows its hint.
- `⌘N`, the toolbar `+` and `Add Book…` open the Add Book sheet. A book added with status Want to Read, Reading or Read appears in the matching list and in All Books, and the sidebar counts update immediately.
- Typing "Thomas Mann" as an author shows "Sorted as: Mann, Thomas". "Johann Wolfgang von Goethe" shows "Goethe, Johann Wolfgang von". Correcting an author's sort name changes the sort position of all that author's books.
- A wrong ISBN check digit shows the red border and "This ISBN is not valid. Check the last digit.", and disables `Add Book` and `Save`. Valid ISBN-10 and ISBN-13 values pass with or without hyphens or spaces.
- Adding a book whose ISBN, or whose title together with an author, is already in the library shows "Already in your library: …" with `Show Book` and `Add Anyway`.
- A cover image can be added by dropping, pasting or `Choose File…` in Add Book and Edit Book, and by dropping it onto the detail pane's cover. It can be removed again. Books without one show the generated coloured cover.
- `Finish Reading…` needs only a finish date and moves the book from Reading to Read. `Abandon` moves it out of Reading, and All Books shows the "Abandoned" badge. `Read Again` adds a new reading with today's start date without creating a second book.
- Double-clicking a reading opens it for editing, and `Delete Reading` removes it.
- New collections can be created, renamed, reordered and deleted. Empty and duplicate names are refused. Deleting a collection keeps its books. Books can be added by dragging, through Add/Edit Book, through `+ Add to Collection`, and through the `Add to Collection ›` submenu, which ticks the book's current collections.
- Each list and collection keeps its own sort order and its own list/grid choice between launches. The default is Author A to Z, then Year Published oldest first. `Reset to Default` restores it. The toolbar button names the current levels.
- Sorting by Title puts "Der Zauberberg" under Z. Sorting by Author puts an author sorted as "Ärger" among the A names. Books without an author or without a value for the sorted field come last.
- Typing "boll" in search finds Böll. `⌘F` focuses the field and `Esc` clears it. With no matches, the list shows "No books match "…"".
- `⌫` and `Delete Book…` ask for confirmation and remove the book with its readings. `⌘Z` undoes it and `⇧⌘Z` redoes it. Every other change can be undone the same way.
- Books, readings, collections, covers, sort choices and view choices are still there after quitting and relaunching.
- Started with `-AppleLanguages '(de)'`, every label, button and status is in German, and dates and counts use German formats ("3. Okt. 2026", "2 Bücher"). The Abandon sheet's confirm button reads `Lektüre abbrechen`.

## Non-goals

- Looking up book data or covers from an online service.
- Barcode scanning.
- The AI assistant.
- iCloud sync and the iOS app.
- Export and import.
- Statistics.
- Collections that fill themselves from a rule.
- Page-by-page reading progress.
- Full publication dates (only the year).
- Half stars.
