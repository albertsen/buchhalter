# iCloud Sync

The library syncs with the user's private iCloud, so it survives the loss of the Mac and is the one library the iPhone and iPad app will share.

Design: https://claude.ai/artifact/KWjhfRAqkfyM8d4sYB3ggT (section "iCloud Sync")

## Problem

1. The library exists only on this Mac, in `~/Library/Application Support/Buchhalter/` (50 MB with covers). If the Mac is lost or its disk fails, the books, readings, ratings and notes are gone. There is no export and no backup: the user decided on 2026-11-15 that iCloud sync is the library's protection.
2. The iPhone and iPad app comes next. It needs the same library, and today there is no way to get the books off the Mac.
3. The app is ad-hoc signed with the bundle id `local.buchhalter`. macOS asks for the Keychain password after every build, when the app first reads the Google Books key ("Always Allow").

## Experience

### Sync is always on

The library syncs whenever the Mac is signed in to iCloud. Buchhalter has no switch for it. A user who does not want sync signs out of iCloud or turns iCloud off for Buchhalter in System Settings; Buchhalter then shows that state (see "When sync can't work").

What syncs:

- Books with their covers, authors, readings, ratings and notes.
- Collections and which books they hold.
- The sort, which applies to every list, and each list's view mode (list or grid).
- The order of the built-in lists in the sidebar (Reading, Want to Read, Read, All Books). Dragging Read above Reading on the Mac changes the order on every device.

What stays on each device and does not sync:

- The book sources, their order and switches, and the Google Books key.
- The selected list and book, the book open in grid mode, the window frame and the column widths.

A change on one device shows up on the others within seconds to minutes, while both are online. Changes made offline are kept and sync once the device is online again. Lists, counts and the detail update by themselves when changes arrive, as they do after a change on the same Mac.

Deleting a book deletes it in iCloud and on every other device, with its readings and cover. `⌘Z` brings it back on the device where it was deleted, until the app quits; the restored book then syncs again.

### First launch of the synced version

The first launch of the signed version moves the library into the app's own place, the container macOS gives a sandboxed app:

- The app copies the library from `~/Library/Application Support/Buchhalter/` into its container. It never changes, moves or deletes the old folder. The old folder is the copy of the library from before the first sync.
- If macOS allows the copy only after the user confirms the folder, an open panel asks once for the old library folder, already showing `~/Library/Application Support/Buchhalter/`. Cancel leaves the old folder alone and starts with an empty library; the next launch asks again.
- Then the whole library uploads to iCloud.

A sheet appears once, over the main window:

- Title: "Your Library Now Syncs with iCloud" / "Deine Bibliothek wird jetzt mit iCloud synchronisiert"
- Text: "Buchhalter keeps your library in your private iCloud. It is safe if this Mac is lost, and the iPhone and iPad app shows the same books." / "Buchhalter bewahrt deine Bibliothek in deiner privaten iCloud auf. Sie ist sicher, wenn dieser Mac verloren geht, und die App für iPhone und iPad zeigt dieselben Bücher."
- "All 79 books are going to iCloud, with their readings, collections and covers. You can keep working meanwhile." / "Alle 79 Bücher gehen mit ihren Lektüren, Sammlungen und Covern in die iCloud. Du kannst währenddessen weiterarbeiten." The number is the library's count, with the catalog's plural rules ("1 book" / "1 Buch").
- "A copy of the library from before the first sync is kept on this Mac." / "Eine Kopie der Bibliothek von vor der ersten Synchronisierung bleibt auf diesem Mac."
- Small grey line: "The sync status is in Settings → iCloud." / "Der Stand der Synchronisierung steht in Einstellungen → iCloud."
- Buttons: `Show Copy in Finder` / `Kopie im Finder zeigen` opens the old library folder in the Finder and leaves the sheet open. `OK` (primary, also `Return` and `Esc`) closes it.

The sheet never appears again, on this Mac or after a relaunch.

The first upload of 50 MB can take minutes. The user keeps working meanwhile. Quitting Buchhalter is safe: the upload goes on at the next launch, from where it stopped.

### A new device

On a Mac, iPhone or iPad that has no library yet, nothing has to be set up besides being signed in to iCloud with the same Apple Account. The library arrives by itself: books appear in the lists as they come in, the counts grow, covers come last and show the generated cover until then.

### Settings → iCloud

The Settings window gets a second tab, `iCloud`, after `Book Lookup`, with a cloud icon. The tab's name is "iCloud" in both languages.

The group `iCloud Sync` / `iCloud-Synchronisierung` starts with:

- "Books, readings, collections and covers are kept in your private iCloud and show up on every Mac, iPhone and iPad signed in to the same Apple Account."
- "Bücher, Lektüren, Sammlungen und Cover liegen in deiner privaten iCloud und erscheinen auf jedem Mac, iPhone und iPad, das mit demselben Apple Account angemeldet ist."

Under it a box shows the status:

| Row | English | German |
|---|---|---|
| Status | Up to date (green dot) | Aktuell |
| Status, while changes go up or come down | Syncing with iCloud… (spinner) | Wird mit iCloud synchronisiert… |
| Last synced | Today, 14:32 | Heute, 14:32 |
| In iCloud | 79 books · 42 MB | 79 Bücher · 42 MB |

Labels: `Status` / `Status`, `Last synced` / `Zuletzt synchronisiert`, `In iCloud` / `In iCloud`. The date and time follow the locale ("Yesterday, 09:10", "3 Nov 2026, 18:05" / "Gestern, 09:10", "3. Nov. 2026, 18:05"). The book count uses the plural rules. Before the first sync has finished, `Last synced` reads "Not yet" / "Noch nicht".

During the first upload or download, the box adds a grey line:

- "The first upload of a large library can take a while. You can keep working, and you can quit Buchhalter: it goes on at the next launch."
- "Das erste Hochladen einer großen Bibliothek kann dauern. Du kannst weiterarbeiten und Buchhalter auch beenden: Es geht beim nächsten Start weiter."

The group `Copy before the first sync` / `Kopie vor der ersten Synchronisierung` says:

- "Before the library first went to iCloud, Buchhalter kept a copy of it on this Mac, from 20 Nov 2026." / "Bevor die Bibliothek zum ersten Mal in die iCloud ging, hat Buchhalter eine Kopie davon auf diesem Mac behalten, vom 20. Nov. 2026."
- The folder `~/Library/Application Support/Buchhalter/` and the button `Show in Finder` / `Im Finder zeigen`.

The date is the day of the first launch of the synced version. The group is not shown on a device that never had a local library, or once the old folder no longer exists.

A small note closes the tab:

- "The book sources, their order and the Google Books key stay on this Mac. They don't sync."
- "Die Buchquellen, ihre Reihenfolge und der Google-Books-Schlüssel bleiben auf diesem Mac. Sie werden nicht synchronisiert."

### When sync can't work

Each problem replaces the status box with a message. The library keeps working in every case: changes are kept on this Mac and sync once the problem is gone.

| Case | Colour | English | German | Button |
|---|---|---|---|---|
| Not signed in to iCloud | amber | Sign in to iCloud to sync. Until then the library stays on this Mac only. | Melde dich bei iCloud an, um zu synchronisieren. Bis dahin bleibt die Bibliothek nur auf diesem Mac. | `Open System Settings…` / `Systemeinstellungen öffnen…` |
| iCloud turned off for Buchhalter | amber | iCloud is turned off for Buchhalter. The library stays on this Mac only and is not protected if the Mac is lost. | iCloud ist für Buchhalter ausgeschaltet. Die Bibliothek bleibt nur auf diesem Mac und ist nicht geschützt, wenn der Mac verloren geht. | `Open System Settings…` / `Systemeinstellungen öffnen…` |
| iCloud storage full | amber | Your iCloud storage is full. New changes stay on this Mac and sync once there is space. | Dein iCloud-Speicher ist voll. Neue Änderungen bleiben auf diesem Mac und werden synchronisiert, sobald Platz ist. | `Manage Storage…` / `Speicher verwalten…` |
| Any other error | red | iCloud sync stopped: <the error iCloud reports>. Your changes are kept on this Mac. Buchhalter tries again at the next launch. | Die iCloud-Synchronisierung wurde angehalten: <der Fehler, den iCloud meldet>. Deine Änderungen bleiben auf diesem Mac. Buchhalter versucht es beim nächsten Start erneut. | none |

`Open System Settings…` opens the Apple Account settings. `Manage Storage…` opens the iCloud storage settings. When the problem is gone (the user signs in, frees space), the status box comes back without a relaunch, and sync continues.

### The line in the sidebar

A line at the bottom of the sidebar shows the sync status, but only:

- during the first upload: "Uploading your library to iCloud…" / "Deine Bibliothek wird in die iCloud geladen…" (spinner)
- during the first download on a new device: "Getting your library from iCloud…" / "Deine Bibliothek kommt aus der iCloud…" (spinner)
- while there is a problem from the table above: "iCloud sync isn't working" / "iCloud-Synchronisierung funktioniert nicht" (amber or red icon)

Clicking the line opens Settings on the `iCloud` tab. Everyday syncs do not show the line, so it does not flicker.

### Changes on two devices

The user switches between the Mac, iPhone and iPad. Nobody is asked to merge anything. Where the same thing changed on two devices, these rules apply:

- The same field of the same book, reading or collection changed on two devices: the later change wins.
- The same author name created on two devices (for example "Thomas Mann", added offline on both): the two become one author. A sort name the user corrected is kept.
- The same collection name created on two devices: the two become one collection, holding the books of both, with the earlier one's note and place in the sidebar.
- The same book added on two devices (the same ISBN): both books stay. The user deletes one by hand.
- A reading started on two devices for the same book: both readings stay; the newer one is the current reading, as today.
- The sort and view modes changed on two devices: the newer setting wins.

`⌘Z` undoes only the user's own actions on this device. A change that arrived from another device is not on the undo stack, and undoing an own action never reverts a change another device made in the meantime to a different field.

### Signing and the Google Books key

The app gets a real bundle id under the user's Apple Developer team, a proper signature and the sandbox. Nothing about this is visible in the app except:

- macOS no longer asks for the Keychain password after each build.
- The Google Books key keeps working without being entered again. If it cannot be carried over, Settings → Book Lookup shows the empty key field once ("Paste your key"), and the user pastes the key one more time. Source order and switches stay as they were.

Builds made with `make app` use the same iCloud data as the later TestFlight and App Store versions (CloudKit's production environment). A separate test store (`BUCHHALTER_HOME`) never syncs and never touches the iCloud data.

### Languages

| English | German |
|---|---|
| iCloud (tab) | iCloud |
| iCloud Sync | iCloud-Synchronisierung |
| Up to date | Aktuell |
| Syncing with iCloud… | Wird mit iCloud synchronisiert… |
| Last synced | Zuletzt synchronisiert |
| Not yet | Noch nicht |
| In iCloud | In iCloud |
| Copy before the first sync | Kopie vor der ersten Synchronisierung |
| Show in Finder | Im Finder zeigen |
| Show Copy in Finder | Kopie im Finder zeigen |
| Open System Settings… | Systemeinstellungen öffnen… |
| Manage Storage… | Speicher verwalten… |
| Your Library Now Syncs with iCloud | Deine Bibliothek wird jetzt mit iCloud synchronisiert |
| iCloud sync isn't working | iCloud-Synchronisierung funktioniert nicht |

"iCloud", "Apple Account", "Finder", "TestFlight" and "App Store" are not translated.

## Goals

- On the first launch of the signed version, the library from `~/Library/Application Support/Buchhalter/` shows with all its books, readings, collections, ratings, notes and covers. The old folder is unchanged afterwards (same files, same sizes).
- The sheet "Your Library Now Syncs with iCloud" appears once, with the library's book count. `Show Copy in Finder` opens `~/Library/Application Support/Buchhalter/`. It does not appear at the next launch.
- Settings has a second tab, `iCloud`, showing "Syncing with iCloud…" during the first upload, then "Up to date", the time of the last sync and the number of books and megabytes in iCloud.
- The sidebar line "Uploading your library to iCloud…" shows during the first upload and disappears when it is done. Clicking it opens Settings → iCloud.
- Quitting during the first upload and launching again continues the upload; no book is missing or doubled in iCloud afterwards.
- A book added on the Mac appears on a second device signed in to the same Apple Account within a few minutes, with its cover. A rating changed on the second device appears on the Mac.
- Deleting a book on one device removes it on the other. `⌘Z` on the first device brings it back on both.
- Dragging a built-in list to a new place in the sidebar changes the order on the other device.
- The source order, the switches and the Google Books key differ per device and stay so after a sync.
- Signed out of iCloud, Settings → iCloud shows the amber "Sign in to iCloud to sync" message with `Open System Settings…`, the sidebar shows "iCloud sync isn't working", and books can still be added and edited. After signing in, the changes sync without a relaunch.
- With iCloud turned off for Buchhalter, Settings shows the amber "iCloud is turned off for Buchhalter" message.
- The same author added offline on two devices ends up as one author after both are online. The same collection name ends up as one collection with the books of both.
- `⌘Z` after a change arrived from another device undoes only the user's own last action.
- Two builds in a row with `make app` read the Google Books key without a Keychain password prompt.
- `make app` builds the signed, sandboxed app. A store under `BUCHHALTER_HOME` never syncs.
- Started in German, the Settings tab, the status texts, the messages, the sidebar line and the one-time sheet are in German:

```
open build/Buchhalter.app --args -AppleLanguages '(de)' -AppleLocale de_DE
```

## Non-goals

- The iPhone and iPad app. It comes as its own spec.
- A switch in Buchhalter to turn sync off or on.
- A button that deletes the whole library from iCloud, or a reset of the iCloud data.
- Export, file backups or dated copies beyond the old library folder.
- Syncing the book sources, their order or the Google Books key.
- Merging duplicate books after a sync. Both stay; the user deletes one.
- Sharing a library with another Apple Account.
- Progress numbers for uploads and downloads ("312 of 1,000").
- Adapting `buchhalter-cli` to the new library location. Left for later.
