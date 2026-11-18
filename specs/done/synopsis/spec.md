# Synopsis

Each book can keep a synopsis, the publisher's blurb or a summary, which Complete and Find Synopsis fetch from the book sources and the book detail shows.

Design: https://claude.ai/artifact/KWjhfRAqkfyM8d4sYB3ggT (section "Synopsis")

## Problem

1. A book on the Want to Read list shows its title, author and cover, but nothing about what it is about. Deciding what to read next means looking each book up on the web.
2. The book sources have the text: the Deutsche Nationalbibliothek links the publisher's blurb for most newer German books, Google Books has a description for many English ones, Open Library for some. Buchhalter drops it today.

## Experience

### In the book detail

On the Mac, the iPhone and the iPad, the book detail shows a section `Synopsis` / `Inhalt` between the header (with its buttons) and `Collections`. The text is in the serif face of the titles, at reading size.

- The text is cut after 4 lines, with `More` / `Mehr` under it. `More` unfolds the whole text in place, and `Less` / `Weniger` folds it again. A text of 4 lines or fewer shows whole, without `More`.
- Next to `More` a grey line names where the text came from: "From the Deutsche Nationalbibliothek" / "Aus der Deutschen Nationalbibliothek", "From Open Library" / "Aus Open Library", "From Google Books" / "Aus Google Books". A synopsis typed or edited by hand has no source line.
- Paragraphs in the text are kept. Formatting from a source (bold, links, HTML tags) is not; the text is plain.
- On the Mac, a click on the text edits it in place, like the title and the other fields of the header: a text area as tall as the whole text opens. Return or a click elsewhere in the detail saves it as one "Edit Book" undo step; ⌥Return or ⇧Return starts a new line; Escape cancels. Selecting another book saves too. An edited text loses its source line.
- A book without a synopsis shows no section at all; Find Synopsis or the editor adds one.
- On the iPhone and iPad, a long press on the text offers `Copy` / `Kopieren`, `Edit…` / `Bearbeiten…` (opens Edit Book on the synopsis) and `Remove Synopsis` / `Inhalt entfernen`.

### Add Book and Edit Book on the Mac

The sheet gets two tabs under the grey hint line: `Details` and `Synopsis` (German `Details` and `Inhalt`). `Details` holds every field the sheet has today, unchanged, and is selected when the sheet opens. `Synopsis` holds one large text area that fills the sheet and scrolls when the text is longer, the source line under it, and a `Remove Synopsis` / `Inhalt entfernen` button.

The text area takes plain text. Typing into it, pasting or clearing it works like any field, and Save saves it with the book as one undo step. The sheet keeps its size when switching tabs.

### Add Book and Edit Book on the iPhone

The editor gets one new row after ISBN: `Synopsis` / `Inhalt`, with the first two lines of the text and a chevron, or "None" / "Keiner" in grey. Tapping it opens a page of its own with the text at full height, the source line, and a `⋯` menu with `Remove Synopsis` / `Inhalt entfernen`. The back button returns to the editor; Cancel and Save stay the editor's. The iPad uses the same row and page.

### Complete

Complete fetches the synopsis together with the other data, from the same sources and in the same order.

- A book without a synopsis gets the found one. The green banner counts it like a field ("Filled in 7 fields…"), and a green dot on the `Synopsis` tab (Mac) or the `Synopsis` row (iPhone, iPad) shows that it was filled. Undo in the banner removes it with the rest.
- A book that has a synopsis keeps it. When the source's text differs, the `Synopsis` tab or page shows "Google Books has a different synopsis · Show · Use" / "Google Books hat einen anderen Inhalt · Zeigen · Übernehmen", with the source's name. `Show` / `Zeigen` shows the source's text under the offer; `Use` / `Übernehmen` replaces the book's text with it. The dot on the tab or row stays while the offer is open.
- Complete never fails because of the synopsis. When no source has one, the book keeps what it has and nothing is said about it.

### Which text is taken

Several sources can have a text for the same book, and a source can have texts in several languages (the Deutsche Nationalbibliothek holds a Russian summary for a Russian edition of *Buddenbrooks*). The sources are asked in the order set in Settings. A text in the book's language wins; a text in another language is taken only when no source has one in the book's language. A book without a language takes the first text found.

The Deutsche Nationalbibliothek's text is the publisher's blurb it links for the book (newer records link it on services.dnb.de, older ones through deposit.dnb.de or d-nb.info), or the summary in its record when there is no blurb.

### Find Synopsis

A book without a synopsis has `Find Synopsis` / `Inhalt suchen` in its context menu (the cover's and the row's, on the Mac and on iOS), next to `Find Cover`. It searches like Find Cover: by the ISBN, then by title and authors, in the sources that are on, with the language rule above.

- While it runs, the menu item is disabled for that book. Nothing else changes until it ends.
- Found: the synopsis is saved at once, as one undo step "Find Synopsis" / "Inhalt suchen", and the section appears in the detail.
- Nothing found: an alert "No synopsis found" / "Kein Inhalt gefunden" with "None of your book sources has a synopsis for this book." / "Keine deiner Buchquellen hat einen Inhalt für dieses Buch." When Google Books has no key or is off, a second sentence and an `Open Settings…` / `Einstellungen öffnen…` button follow, as in Find Cover's alert.
- No source reachable: the same alert as Find Cover's for that case, with "synopsis" in place of "cover".
- A synopsis typed into Edit Book while it runs wins; the found one is dropped.
- No source on: the item is disabled, as Find Cover is.

### Scanning

The scan card on the iPhone and iPad and Add Book on the Mac fetch the synopsis with the rest of the data. The card does not show it; `Add and Scan Next` saves it with the book, and the detail shows it.

### Sync and existing books

The synopsis is part of the book and syncs to every device with it. Books added before this feature have none until Complete in Edit Book or Find Synopsis gives them one; there is no command that fills all books at once.

## Goals

- Complete on a new German book with an ISBN fills the `Synopsis` tab with the publisher's blurb and the line "From the Deutsche Nationalbibliothek"; the banner counts it and the tab shows the dot.
- Complete on an English book that Google Books knows fills the synopsis with "From Google Books".
- The book detail shows the synopsis cut to 4 lines with `More`; `More` and `Less` unfold and fold it, on the Mac and the iPhone.
- A book without a synopsis shows no `Synopsis` section.
- `Find Synopsis` on an existing book without one saves a synopsis; ⌘Z (Mac) or shake (iPhone) removes it again.
- `Find Synopsis` on a book no source knows shows "No synopsis found".
- Complete on a book whose synopsis was typed by hand keeps that text and offers the source's with `Show · Use`.
- A German book never gets an English or Russian text when a source has a German one.
- A synopsis added on the Mac appears on the iPhone.
- All texts of the feature appear in German with the app in German.
- The Details tab of Add and Edit Book on the Mac looks as it does today.

## Non-goals

- No command that fills the synopsis of every book at once, in the app or in `buchhalter-cli`.
- Search does not look in the synopsis.
- No rich text: no bold, italics or links, in the detail or the editor.
- The synopsis is not shown on the scan card, in the book list or in the grid.
- No translation of a synopsis into the app's language.
