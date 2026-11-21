# Author List

A new Library list, Authors, shows every author in the library by sort name; choosing an author shows their books, oldest first.

Design: https://claude.ai/artifact/KWjhfRAqkfyM8d4sYB3ggT (section "Author List")

## Problem

1. Seeing what the library holds by one author means typing the name into the search field of All Books. The result is sorted by whatever All Books is sorted by, not by when the books came out.
2. There is no overview of the authors themselves: who is in the library, and with how many books.

## Experience

### The Authors row

The Library section gets a fifth row, `Authors` / `Autoren`, after `All Books`, with a person icon and a count: the number of authors who have at least one book. It is in the Mac's sidebar, on the iPhone's Library screen and in the iPad's sidebar. It moves like the other four rows (drag on the Mac, Edit on iOS), and its place syncs with theirs.

### The list of authors

Choosing `Authors` shows the authors instead of books in the middle column; on the iPhone it is a screen of its own. The title is "Authors" / "Autoren", the subtitle the count: "1 author", "48 authors" / "1 Autor", "48 Autoren".

- Only authors with at least one book are listed. An author whose last book is deleted leaves the list, and comes back when a book by them is added.
- The order is the sort name ("Mann, Thomas"), with German collation, ignoring case and accents, as book sorting does. Each author sits under a header with the first letter of the sort name: Thomas Mann under M, Johann Wolfgang von Goethe under G (the particle is not part of the sort key). Ä, Ö and Ü go under A, O and U. A sort name that starts with something other than a letter goes under `#`.
- Each row shows the name as written ("Thomas Mann") and the author's number of books.
- On the iPhone the right edge has an A–Z index; touching a letter jumps to it.
- There is no Sort button and no List/Grid switch. The order is fixed.
- The `+` button opens Add Book empty, as from any list.
- Until an author is chosen, the right column shows "No Author Selected" / "Kein Autor ausgewählt" with "Choose an author to see their books." / "Wähle einen Autor aus, um die Bücher zu sehen."

### Searching authors

The search field reads "Search Authors" / "Autoren suchen" and filters the authors (never the books) as the user types, by name and sort name, ignoring case and accents: "boll" finds Heinrich Böll. When nothing matches: "No authors match “rilke”" / "Keine Autoren passen zu „rilke“". `⌘F` and `Esc` work as in the other lists.

### Empty library

With no books, the list shows "No authors yet" / "Noch keine Autoren" with "Authors appear here as you add their books." / "Autoren erscheinen hier, sobald du ihre Bücher hinzufügst." The subtitle reads "No authors" / "Keine Autoren".

### An author's books

Choosing an author shows their books in the right column, next to the authors, which stay in view. Clicking a book shows its detail in place of the books; on the Mac a `‹ Books` / `‹ Bücher` button over the detail goes back to them, on iOS the back button in the navigation bar. The iPad in portrait slides the author list away when an author is chosen. On the iPhone the books are the next screen after Authors, and a book the one after that. The title is the author's name, the subtitle the count ("4 books" / "4 Bücher").

- The order is Year Published, oldest first. Books from the same year are sorted by title (ignoring a leading article); books without a year come last.
- Each row shows the cover, the title, the year where other lists show the author, and the status line ("Started 3 Oct 2026", "Finished 14 Aug 2021", "Abandoned 5 Nov 2026"), as in the other lists. A book without a year shows no year.
- A book by several authors is listed under each of them. Its row names the others after the year: "1959 · with Lisa Seidl" / "1959 · mit Lisa Seidl".
- Rows work as in every list: the context menu, the swipe actions on iOS, dragging a book onto a collection on the Mac, and Delete Book….
- There is no Sort button and no List/Grid switch.
- The `+` button opens Add Book with this author as the first author chip; the chip can be removed like any other.
- When the author has no books left (the last one is deleted, or Edit Book removes the author from it), the right column goes back to "No Author Selected".

### Edit Sorted As

Right-clicking an author (Mac) or a long press on one (iOS) shows `Edit Sorted As…` / `Sortierung bearbeiten…`. It opens a small sheet titled with the author's name, with one field, "Sorted as" / "Sortiert als", filled with the current sort name, and `Cancel` and `Save`. An empty field disables `Save`.

Saving changes the sort name for all of the author's books, as the `Edit` link in Add Book does. It is one undo step, "Edit Sorted As" / "Sortierung bearbeiten", and the author moves to their new place in the list, under the new letter. Book lists sorted by Author follow the new sort name too.

### Remembered and synced

The Mac reopens Authors at launch when it was the selected list, with the author whose books were open and the book selected in them. Authors, sort names and the sidebar order sync as they do today; the list needs nothing of its own to sync.

## Goals

- The sidebar (Mac, iPad) and the Library screen (iPhone) show `Authors` after `All Books`, with the number of authors who have books.
- Authors lists Thomas Mann under M, Johann Wolfgang von Goethe under G and Gabriel García Márquez under G, each with their number of books.
- An author whose only book is deleted disappears from Authors.
- Choosing Thomas Mann shows Buddenbrooks (1901), Tonio Kröger (1903), Der Zauberberg (1924) and Doktor Faustus (1947), in that order.
- A book with two authors appears under both, with "with …" naming the other.
- "boll" in Search Authors finds Heinrich Böll; "rilke" shows "No authors match “rilke”".
- `Edit Sorted As…` on "García Márquez, Gabriel" set wrongly to "Márquez, Gabriel García" moves him from M to G; ⌘Z (Mac) or shake (iPhone) moves him back.
- `+` with Thomas Mann open opens Add Book with Thomas Mann as the first author.
- On the iPhone, Library → Authors → Thomas Mann → Buddenbrooks, and back again with the back buttons.
- On the Mac, quitting with an author open and launching again shows the same author's books.
- All texts of the feature appear in German with the app in German.

## Non-goals

- The author name in the book detail stays as it is; it does not open the author.
- No renaming or merging of authors from the Authors list.
- No author photos, biographies or dates.
- No sort options and no grid view for Authors or an author's books.
- The iPhone's "Search All Books" on the Library screen does not find authors.
