# UI

Each feature's design in the [design canvas](https://claude.ai/artifact/KWjhfRAqkfyM8d4sYB3ggT) decides the screens. Overview: [architecture.md](architecture.md).

The visual language: a deep green accent (#1F6F5C), serif (New York) titles, a fixed palette of 11 generated cover colours.

## The app's own controls

- `StatusSegments` looks like a segmented control, but clicking the selected segment clears it: a system segmented `Picker` cannot deselect, and the status is optional.
- `SecondaryButtonStyle` for the detail's secondary buttons: a primary-colour label on a neutral fill. On macOS 27 a bordered button draws its label in the tint, dark green on dark grey in dark mode. Only the prominent action uses the accent.
- Pop-up and link buttons draw in the tint too, so the sort popover uses the system colours (`.tint(nil)`).
- `DateField`: a button with the day that opens a graphical calendar in a popover, which closes on a pick. The system date field's calendar stays open.
- `OptionalDatePicker` for dates that may be missing (Started and Finished on in the editor, the dates in Edit Reading): the same button, or "Optional" in grey without a date. The calendar offers Today when no day is set (picking the already selected day changes nothing) and Remove Date when one is. No checkbox.
- `StarRatingControl` sets half stars: a first click on a star gives it whole, a second makes it half (`StarClick`). Arrow keys and VoiceOver step in halves.

## Sheets

- Sheet forms use a `Grid` whose label column grows to the widest label; German labels run longer than the design's 70 pt.
- The editor (650 pt on the Mac) sizes to its content instead of scrolling, so hints and notes make it taller. On iOS it is a `NavigationStack` with a scroll view, Cancel and Add or Save in the toolbar, and a keyboard that can be dismissed.
- Add and Edit Book have two parts. On the Mac, `EditorTabs` under the hint line switch between Details (every field) and Synopsis (`SynopsisEditor`: a text area, the source line, Remove Synopsis, the offer); the Synopsis pane takes the Details pane's measured height. On iOS a Synopsis row after ISBN (two lines or "None") pushes the same `SynopsisEditor` as a page with a ⋯ menu. A green dot on the tab or row shows a synopsis Complete filled or offers. `ActiveSheet.editSynopsis` opens the editor on it.
- The editor's header holds Complete (`LookupHeader`, see [lookup.md](lookup.md)): an explanation, a status line, an amber or red hint, or a green banner with Undo. Filled fields get a light green fill (`lookupFilled`), differing fields a note (`LookupOfferNote`).
- Finished on is optional like Started. Leaving or saving the ISBN field rewrites a valid ISBN as hyphenated ISBN-13.

## Book detail

- Buttons follow the current reading: Start Reading and Edit for Want to Read (`Library.startReading`: Reading, started today, one undo step), Finish Reading…, Abandon… and Edit while reading, Read Again and Edit otherwise. The same status actions are in the book's context menu and the Mac's Book menu.
- Fields edit in place (`InlineFields.swift`): a click turns a field into a text field, Return or clicking elsewhere saves, Escape cancels. A value the library refuses keeps the field open with a red outline. Languages are menus, Date Added a calendar. Each change is one "Edit Book" undo step through `Library.updateDetails`.
- Empty fields show their placeholders on hover on the Mac, always on iOS.
- `SynopsisSection` sits between the header and Collections: the text in the serif face, cut after four lines with More and Less (measured against a hidden full copy), and the "From …" line. No section without a synopsis. On the Mac a click edits it in place: a `TextEditor` as tall as its text (a hidden copy sizes it), Return or a click elsewhere saves through `updateDetails` ("Edit Book"), ⌥Return or ⇧Return is a new line, Escape cancels, and a change of book saves to the book that was edited. An invisible focusable view behind the detail takes focus on a click into empty space, because macOS keeps a text view focused otherwise. On iOS a long press offers Copy, Edit… and Remove Synopsis.
- The cover takes a dropped or pasted image (Mac), the Photos picker or the camera (iOS, `PhotoCapture`), and offers Find Cover when it has none.

## Mac

- One main window (one `Window` scene, so one undo stack; closing it quits). List mode: a three-column `NavigationSplitView` with the sidebar (the built-in lists in the user's order, then the collections), the list and the detail. Grid mode: the sidebar and the grid; opening a book pushes its detail with a back button.
- The Book menu and ⌘N, ⇧⌘N, ⌘F and ⌘⌫ cover the common actions.
- `Settings` scene (⌘,): two tabs, Book Lookup and iCloud, 620 pt wide. The panes and the key help sheet are shared views under `Views/Settings`. The sources are a bordered `List` with checkboxes and drag handles.
- The sidebar's bottom shows `SidebarSyncLine` during a first transfer or a problem; a click opens the iCloud tab.
- **Saved per Mac in UserDefaults:** `scanCamera`, `scanInARow`, `lookupSources`, `googleBooksKeyState` (no secret), `selectedList`, `selectedBook`, `openBook`, `sidebarWidth`, `listWidth`, `settingsTab`, and the sync keys (`legacyCopyDate`, `syncNoticeShown`, `iCloudLastSynced`, `iCloudFirstTransfer`). The order of the built-in lists is in the store, so it syncs.
- **Window frame and columns:** SwiftUI restores the frame only through state restoration (skipped when "Close windows when quitting an application" is on), places new windows on the main display, and lays the columns out at their ideal widths. `restoresWindowFrame(named:)` saves AppKit's frame descriptor (which names the display) under `WindowFrame main` and the column widths, and applies them when the window first becomes key.

## iPhone and iPad

- One `RootView` for every device. The iOS parts come from three modifiers in `PhoneRootChrome.swift` (`phoneSidebarChrome`, `phoneListChrome`, `phoneWindowChrome`): the gear for the settings sheet, the sidebar's Edit button, a bottom bar (New Collection; on the iPhone also Scan and Add), the list toolbar (search, the Sort and View menu, Scan on the iPad, Add), the full-screen scanner, and hidden ⌘N, ⇧⌘N and ⌘⌫ for a hardware keyboard.
- Rows swipe right for the next step (Start Reading, Finish Reading…) and left for Delete, which asks first. Undo is the system's (shake, three-finger swipe). Context menus are long-press menus.
- Settings is a sheet (`PhoneSettingsView`) with the shared panes stacked: the sources as rows with a switch and drag handles, the key section, iCloud.
- Inside the split view's columns iOS reports a compact width even on an iPad, so iPad checks use `UIDevice.current.userInterfaceIdiom`.
- **iPhone:** portrait only. The split view collapses to Library → list → detail. Small-screen layouts are size-class branches, not copies: the detail stacks the cover over the header, the grid uses columns from 90 pt.
- **iPad:** landscape keeps sidebar, list and detail open (`.balanced`). Portrait uses `.prominentDetail`: it starts with the list over the detail. Picking a list keeps the sidebar and the book list open in list mode (hiding only the sidebar makes the split view jump the book list to the left edge while the sidebar slides) and slides the sidebar away in grid mode; tapping a book slides the overlays away and shows the detail alone. `RootView` sets the column visibility from `onGeometryChange`, so rotating to landscape opens all columns again.

## Decisions

- **One `RootView` for every device.** The split view collapses on the iPhone into the design's Library → list → detail flow, and the iPad gets the Mac's columns. iOS adds its bars and gestures through modifiers in `iOS/`, so the Mac's view code stays as it is.
