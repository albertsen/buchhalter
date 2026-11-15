# Google Books

A Settings window lets the user choose which book sources Complete and Find Cover ask and in what order, and adds Google Books as a third source that uses the user's own API key.

Design: https://claude.ai/artifact/KWjhfRAqkfyM8d4sYB3ggT (section "Settings & Google Books")

## Problem

1. English books from the UK and the US often get no cover. The Deutsche Nationalbibliothek holds no UK or US editions, so these books depend on Open Library alone. In a sample of 30 English books from the library, all with an ISBN, 4 got no cover from Find Cover. One of them is "The Garden" by Nick Newman (Penguin 2026): Open Library has one edition of it, and that edition has no cover. Google Books usually has covers for new UK and US editions like this one.
2. The order of the sources is fixed: first the Deutsche Nationalbibliothek, then Open Library. For a library that is mostly English, the DNB is asked first for every book and finds nothing, and the user cannot change this.
3. When the Deutsche Nationalbibliothek cannot be reached, the lookup stops with a red hint. Open Library is not asked, even when it would have the book.
4. Google Books does not work reliably without a key. Requests without a key share one public quota and fail with "quota exceeded". Each user needs their own free key from the Google Cloud Console, and Buchhalter has no place to enter one. The app will go to the Mac App Store, so other users must be able to set this up on their own. No key can ship with the app.

## Experience

### The Settings window

`Buchhalter → Settings…` / `Buchhalter → Einstellungen…` (`⌘,`) opens a standard Mac settings window, 620 pt wide. Its toolbar has one tab, `Book Lookup` / `Buchsuche`, with a magnifier icon. The window title is the name of the tab. The toolbar leaves room for more tabs later. If the window is already open, `⌘,` brings it to the front.

The pane has two groups: `Sources` / `Quellen` and `Google Books`.

### Sources

The group starts with one line:

- "Complete and Find Cover ask the sources that are on, from top to bottom. Drag a source to change the order."
- "Vervollständigen und Coverbild suchen fragen die eingeschalteten Quellen von oben nach unten. Zieh eine Quelle, um die Reihenfolge zu ändern."

Under it is a list of three rows. Each row has a checkbox on the left, the source name, a short grey description on the right and a drag handle (three lines) at the far right:

| Source | Description (English) | Description (German) |
|---|---|---|
| Deutsche Nationalbibliothek | Books published in Germany | In Deutschland erschienene Bücher |
| Open Library | Mostly English books | Vor allem englische Bücher |
| Google Books | badge, see below | badge, see below |

The Google Books row shows a badge where the other rows show a description:

- Without a saved key: "Needs a key" / "Schlüssel nötig". The checkbox is off and disabled, and the name is grey.
- With a saved key: "Set up" / "Eingerichtet". The checkbox works like the other two.

A new user starts with the Deutsche Nationalbibliothek on, then Open Library on, then Google Books last, off and disabled.

The checkbox switches a source on or off. Dragging a row by its handle moves it, and the other rows make room. Google Books can be dragged even while it has no key, so the user can choose its place before turning it on. Changes take effect at once. There is no Save button for the list. Order and switches are kept across launches. They are stored on this Mac, not in the library.

A small note sits under the list:

- "Google Books can be turned on once a key is saved below. With every source off, Complete and Find Cover are unavailable."
- "Google Books lässt sich einschalten, sobald unten ein Schlüssel gesichert ist. Sind alle Quellen aus, sind Vervollständigen und Coverbild suchen nicht verfügbar."

One order and one set of switches apply to both Complete and Find Cover.

### Google Books: entering a key

The group starts with:

- "Google Books has covers for many English editions the other sources miss. It needs your own API key, which Google gives out for free."
- "Google Books hat Cover für viele englische Ausgaben, die den anderen Quellen fehlen. Dafür brauchst du einen eigenen API-Schlüssel, den Google kostenlos vergibt."

Without a saved key, the row `API Key` / `API-Schlüssel` has a secure field with the placeholder "Paste your key" / "Schlüssel einfügen" and a `Save Key` / `Schlüssel sichern` button. The button is disabled while the field is empty. `Return` in the field does the same as the button.

Under the row are the link `How to get a key…` / `So bekommst du einen Schlüssel…` and a small grey note:

- "The key is stored in your Keychain. Searches send the book's ISBN, or its title and author, to Google."
- "Der Schlüssel liegt in deinem Schlüsselbund. Suchen schicken die ISBN oder Titel und Autor des Buchs an Google."

### Checking the key

`Save Key` checks the key with one search at Google Books before it is saved. During the check:

- The button reads "Checking…" / "Wird geprüft…" with a spinner, and is disabled.
- The field stays filled.
- A line reads "Saving checks the key with one search at Google Books." / "Beim Sichern wird der Schlüssel mit einer Suche bei Google Books geprüft."

The check ends in one of three ways.

**The key works.** The key is saved. The field turns into the masked key: dots and the last four characters, such as "•••••••••••••••••a3F9". Next to it are `Change…` / `Ändern…` and `Remove` / `Entfernen`. The badge in the sources list changes to "Set up" / "Eingerichtet", and Google Books is switched on where it stands in the list. A green line appears under the key:

- Google Books in last place: "The key works. Google Books is now on, as the last source." / "Der Schlüssel funktioniert. Google Books ist jetzt eingeschaltet, als letzte Quelle."
- Google Books dragged elsewhere before: "The key works. Google Books is now on." / "Der Schlüssel funktioniert. Google Books ist jetzt eingeschaltet."

When the pane is opened again later, the line reads "The key works. Google Books is on." / "Der Schlüssel funktioniert. Google Books ist eingeschaltet." If the user has switched Google Books off, it reads "The key works. Google Books is off." / "Der Schlüssel funktioniert. Google Books ist ausgeschaltet." The small "Powered by Google" stands under the line in both languages.

**Google rejects the key.** The key is not saved. The field keeps the text and gets a red border. `Save Key` is enabled again. A red message reads:

- "Google didn't accept this key. Check that you copied all of it and that the Books API is turned on for it. The key was not saved."
- "Google hat diesen Schlüssel nicht angenommen. Prüfe, ob du ihn vollständig kopiert hast und ob die Books API für ihn eingeschaltet ist. Der Schlüssel wurde nicht gesichert."

The red border and message go away when the user edits the field.

**Google Books cannot be reached.** The key is not saved yet. An amber message reads:

- "Can't reach Google Books to check the key. Check the internet connection."
- "Google Books ist nicht erreichbar, um den Schlüssel zu prüfen. Prüfe die Internetverbindung."

Next to it is the link button `Save Anyway` / `Trotzdem sichern`. It saves the key without a check and treats it like a working key: masked, the badge reads "Set up", and Google Books is switched on where it stands. The line under the key reads "The key is saved but not checked yet." / "Der Schlüssel ist gesichert, aber noch nicht geprüft." The first lookup that reaches Google Books checks it. `Save Key` tries the check again.

### Changing and removing the key

`Change…` replaces the masked key with an empty field, `Save Key` and `Cancel` / `Abbrechen`. A new key goes through the same check. If the check fails, the old key stays saved and in use. `Cancel` or `Esc` brings back the masked old key.

`Remove` deletes the key at once. Google Books is switched off, its checkbox is disabled, and the badge reads "Needs a key" again. It keeps its place in the list. The field is empty, as for a new user.

The key is kept in the Keychain of this Mac only. After saving, it is never shown in full again. It is not stored in the library file, it does not sync, and it never appears in a log.

### A key that stops working

Google can reject a key that worked before, for example when the user revokes it in the Google Cloud Console or its quota is used up. A lookup then treats Google Books as not reachable and asks the next source (see "When a source can't be reached"). The Settings pane shows a red line under the masked key instead of the green one:

- "Google didn't accept the key. Check it or enter a new one."
- "Google hat den Schlüssel nicht angenommen. Prüfe ihn oder gib einen neuen ein."

Google Books stays on. The red line goes away once a lookup succeeds with the key again or a new key is saved.

### How to get a key

`How to get a key…` opens a sheet over the Settings window, titled "Get a Google Books Key" / "Google-Books-Schlüssel bekommen". It says the key is free and that a Google account is needed. Then it lists the steps:

1. Sign in to the Google Cloud Console with your Google account. / Melde dich mit deinem Google-Konto in der Google Cloud Console an.
2. Create a project, for example "Buchhalter". / Leg ein Projekt an, zum Beispiel „Buchhalter“.
3. Turn on the Books API for the project. / Schalte für das Projekt die Books API ein.
4. Create an API key under Credentials. / Erstelle unter „Anmeldedaten“ einen API-Schlüssel.
5. Restrict the key to the Books API. / Beschränke den Schlüssel auf die Books API.
6. Copy the key and paste it into Buchhalter's Settings. / Kopiere den Schlüssel und füge ihn in Buchhalters Einstellungen ein.

The step names match the labels in Google's console. The footer has `Open Google Cloud Console` / `Google Cloud Console öffnen`, which opens the console in the browser and leaves the sheet open, and `Done` / `Fertig` (the primary button, also `Return` and `Esc`), which closes the sheet.

### Google Books in Complete

Google Books is a full source, like the Deutsche Nationalbibliothek and Open Library. Complete asks the sources that are on, in the order from Settings. The next source is asked only when the one before found nothing or could not be reached. The first source that finds the book supplies the result.

From Google Books, Complete fills the same fields as from the other sources where Google has them: subtitle, authors, year, pages, language, publisher, ISBN and cover. When Google Books finds several editions, "Choose an edition" lists them, newest first, as for the other sources.

Every message names Google Books the same way it names the other sources:

| Place | English | German |
|---|---|---|
| Status line | Searching Google Books for "The Garden" by Nick Newman… | Suche in Google Books nach „The Garden“ von Nick Newman… |
| Banner | Filled in 6 fields from Google Books. Check them, then add the book. | 6 Felder aus Google Books ergänzt. Prüfe sie, dann füge das Buch hinzu. |
| Field note | Google Books: 2009 · Use | Google Books: 2009 · Übernehmen |
| Cover offer | Use Google Books cover | Google-Books-Cover übernehmen |

Google requires attribution wherever its results are shown. When the editions in "Choose an edition" come from Google Books, the sheet shows Google's "powered by Google" logo next to the list, and each row has a link `Google Books` that opens the book's page on Google Books in the browser. Rows from the other sources look as before.

The status line always names the source being asked at that moment. When a source finds nothing, it switches to the next one.

The grey line under the sheet title no longer names one source:

- "Type a title and author, or an ISBN. Complete looks up the rest in your book sources, including the cover."
- "Gib einen Titel und Autor oder eine ISBN ein. Vervollständigen sucht den Rest in deinen Buchquellen, auch das Cover."

Only printed books count, as with the other sources. E-books and audiobooks from Google Books are never matches. Google's "image not available" placeholder picture counts as no cover. It is never filled in or offered.

### Google Books in Find Cover

Find Cover asks the sources that are on, in the order from Settings. For each source it searches by ISBN, then by title and author, as today. The first real cover found is used. With Google Books on, "The Garden" by Nick Newman (ISBN 978-1-80499-375-0) gets its cover.

When no source that is on has a cover, an alert opens:

- Title: "No cover found" / "Kein Coverbild gefunden"
- Message: "None of the sources that are on has a cover for this book." / "Keine der eingeschalteten Quellen hat ein Coverbild für dieses Buch."
- Button: `OK`.

If Google Books has no key or is switched off, the message gets a second sentence, and the alert offers `Open Settings…` / `Einstellungen öffnen…` as the primary button next to `OK`:

- "Google Books often has one: add a key and turn it on in Settings."
- "Google Books hat oft eins: Trag in den Einstellungen einen Schlüssel ein und schalte es ein."

`Open Settings…` closes the alert and opens Settings on the `Book Lookup` pane.

### When a source can't be reached

A source that cannot be reached (no internet connection, timeout, server error, or a key Google rejects) is skipped, and the next source that is on is asked. This applies to Complete and Find Cover alike. It replaces the old rule that a failure of the Deutsche Nationalbibliothek ends the lookup.

When at least one source answered and none found the book, Complete shows the amber no-match hint as before.

When no source that is on could be reached, Complete shows a red hint with `Try Again` / `Erneut versuchen`:

- "Can't reach any book source. Check the internet connection. You can still add the book by hand."
- "Keine Buchquelle ist erreichbar. Prüfe die Internetverbindung. Du kannst das Buch trotzdem von Hand eintragen."

When only one source is on, the hint names it, as before. For Google Books: "Can't reach Google Books. Check the internet connection. You can still add the book by hand." / "Google Books ist nicht erreichbar. Prüfe die Internetverbindung. Du kannst das Buch trotzdem von Hand eintragen."

Find Cover shows an alert in the same case: "Can't reach any book source" / "Keine Buchquelle erreichbar", with the message "Check the internet connection." / "Prüfe die Internetverbindung." and `OK`.

### Every source off

With every source off in Settings:

- `Complete` in Add Book and Edit Book is disabled, with the tooltip "Turn on a source in Settings" / "Schalte in den Einstellungen eine Quelle ein".
- The `Find Cover` button over the generated cover and the item in the cover's context menu are disabled, with the same tooltip.

Switching a source on enables both at once, including in an open sheet.

### Languages

| English | German |
|---|---|
| Settings… | Einstellungen… |
| Book Lookup | Buchsuche |
| Sources | Quellen |
| Needs a key | Schlüssel nötig |
| Set up | Eingerichtet |
| API Key | API-Schlüssel |
| Paste your key | Schlüssel einfügen |
| Save Key | Schlüssel sichern |
| Checking… | Wird geprüft… |
| Save Anyway | Trotzdem sichern |
| Change… | Ändern… |
| Remove | Entfernen |
| Cancel | Abbrechen |
| How to get a key… | So bekommst du einen Schlüssel… |
| Get a Google Books Key | Google-Books-Schlüssel bekommen |
| Open Google Cloud Console | Google Cloud Console öffnen |
| Done | Fertig |
| No cover found | Kein Coverbild gefunden |
| Open Settings… | Einstellungen öffnen… |
| Use Google Books cover | Google-Books-Cover übernehmen |
| Turn on a source in Settings | Schalte in den Einstellungen eine Quelle ein |
| Try Again | Erneut versuchen |

The names "Google Books", "Google Cloud Console", "Books API", "Deutsche Nationalbibliothek", "DNB" and "Open Library" are not translated. "Powered by Google" stays in English in both languages.

## Goals

- `⌘,` and `Buchhalter → Settings…` open the Settings window with the `Book Lookup` pane.
- A new user sees the Deutsche Nationalbibliothek and Open Library on, in that order, and Google Books last, off and disabled, with "Needs a key".
- Unchecking Open Library means Complete and Find Cover never ask it. The status line never names it.
- Dragging Google Books to the top makes Complete ask it first. The status line names Google Books first.
- With every source off, `Complete` and `Find Cover` are disabled, with the tooltip "Turn on a source in Settings".
- `Save Key` is disabled while the field is empty, and shows "Checking…" with a spinner during the check.
- A wrong key shows the red message, keeps the text with a red border, and is not saved. Google Books stays disabled.
- A working key is shown masked with its last four characters, the badge reads "Set up", and Google Books is switched on as the last source, with the green message.
- With the network off, `Save Key` shows the amber message, and `Save Anyway` saves the key and switches Google Books on.
- `Change…` followed by `Esc` keeps the old key. `Remove` deletes the key and switches Google Books off, with "Needs a key".
- The full key is never shown again after saving and does not appear in the library file.
- `How to get a key…` opens the help sheet with the steps. `Open Google Cloud Console` opens the console in the browser.
- Once Google Books is on, Find Cover finds a cover for "The Garden" by Nick Newman (ISBN 978-1-80499-375-0).
- A book Complete fills from Google Books shows "from Google Books" in the banner and "Google Books: <value> · Use" in its notes.
- "Choose an edition" with results from Google Books shows the "powered by Google" logo, and each row's `Google Books` link opens that book's Google Books page.
- Google's "image not available" picture is never used as a cover. E-books and audiobooks from Google Books never appear as matches.
- Without a cover result and without Google Books set up, Find Cover shows "No cover found" with the Google Books sentence and `Open Settings…`, which opens the `Book Lookup` pane.
- With the Deutsche Nationalbibliothek unreachable, Complete moves on to the next source and fills the sheet from it.
- With the network off, Complete shows the red "Can't reach any book source" hint only after every source that is on has failed. The book can still be added by hand.
- Order, switches and key survive a relaunch.
- Started in German, the menu item, the Settings window, all messages, the help sheet, the tooltips and the Find Cover alert are in German:

```
open build/Buchhalter.app --args -AppleLanguages '(de)'
```

## Non-goals

- A key that ships with the app, or a shared key.
- Other sources, such as Amazon or ISBNdb.
- A separate source order for Complete and for Find Cover.
- Settings on iPhone and iPad. They come with the iOS app.
- The Assistant pane and keys for AI providers.
- Finding covers for many books at once.
- Showing the full key after it is saved.
- Usage statistics or a quota display.
- Syncing the source settings or the key between devices.
