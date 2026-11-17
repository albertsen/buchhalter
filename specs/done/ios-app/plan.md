# iOS App — Plan

## Current State (audited 2026-11-17)

- **Targets:** `Package.swift` (tools 6.2, Swift 6 mode) has `BuchhalterCore`, `BuchhalterKeychain`, the executable `Buchhalter` (`defaultIsolation(MainActor)`), `BuchhalterCLI` and the tests. Platforms already include `.iOS("27.0")`, but nothing has ever been compiled for iOS. `BuchhalterKeychain` is a target, not a library product.
- **Toolchain:** Xcode 27.2 (27B52), SDKs `iphoneos27.2`, `iphonesimulator27.2`, `macosx27.2`. One signing identity (Apple Development, U4QMFKCJC7); Xcode is signed in to the developer account. Paired: "jaPhone", iPhone17,1 (16 Pro), UDID `00008140-00067C920A60801C`; no iPad yet. Only the macOS profile exists.
- **App entry:** `App/BuchhalterApp.swift` is Mac-only in practice (`@NSApplicationDelegateAdaptor`, `Window`, `Settings`, schema initializer, legacy copy, `StoreFailureAlert`, `.commands`), though it sits in the shared `App/`.
- **Root view:** `Views/RootView.swift` holds the `NavigationSplitView` (three columns in list mode; sidebar + `NavigationStack` in grid mode), `.searchable(placement: .toolbar)`, `LibraryToolbar`, the sheets, delete confirmations ("You can undo it with ⌘Z.") and `.frame(minWidth: 900, minHeight: 560)`.
- **Mac-only APIs in shared views** (iOS 27.2 SwiftUI interface): `onExitCommand` (`CollectionRow.swift:76`) and `navigationSubtitle` (`librarySubtitle`) are unavailable on iOS; `onDeleteCommand`, `onHover`, `swipeActions`, `searchFocused` and `focusedSceneValue` are available.
- **Library operations:** no operation turns a Want to Read reading into Reading; `readAgain` refuses `wantToRead`.
- **Keychain:** `KeychainSecretStore` (service `Buchhalter Google Books`, account `api-key`) sets no access group and no `kSecAttrSynchronizable`. The entitlement group is `3PT9KVM9AJ.de.juergenalbertsen.buchhalter`.
- **Scanning:** `ScanSession` (effects `playSound`, `openEditor`, `fillField`), `ScanRound`, `ScanGeometry` (`mirrored:` flag, aspect fill) and `CameraChoice` are core. `BarcodeCamera` discovers the Mac's set (wide angle, Continuity, external, any position). `CameraPreviewLayer` and `ScanFeedback.mac` are Mac-only; the `ScanFeedback` entry lives in `ScanSheet.swift`.
- **Sync:** the Mac's `SyncActionsModifier` fills the `SyncActions` closures; `CloudSyncMonitor` is portable.
- **Lookup:** `LookupModel` holds `phase` and `result` over a `BookDraft`.
- **Permissions:** `.claude/settings.json` allows `swift build`, `swift test`, `make`, `xcrun xcstringstool`, `BUCHHALTER_HOME=*`; `.claude/settings.local.json` (gitignored, added at the user's request) allows `xcodebuild`.

## Research

Checked against the installed Xcode 27.2 SDKs.

- **Synchronized folders** (`PBXFileSystemSynchronizedRootGroup`, Xcode 16+): files in a referenced folder join the target without pbxproj edits. Source: Xcode 16 release notes.
- **Default isolation:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` matches the package's `.defaultIsolation(MainActor.self)`. Source: Xcode 26 release notes.
- **Automatic signing:** `xcodebuild -allowProvisioningUpdates` with `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = 3PT9KVM9AJ` registers connected devices and creates the iOS profile for the existing App ID `de.juergenalbertsen.buchhalter` (iCloud and container already on). Source: `man xcodebuild`.
- **Install:** `xcrun devicectl device install app --device <name or UDID> <path>.app`. Source: `xcrun devicectl help device install`.
- **CloudKit on iOS** needs the background mode `remote-notification` and `aps-environment` for pushes of remote changes; without them changes arrive only on foregrounding. Source: "Setting Up Core Data with CloudKit".
- **iCloud Keychain** (`Security/SecItem.h:88-102`, developer.apple.com/documentation/security/ksecattrsynchronizable): `kSecAttrSynchronizable = true` syncs a generic password; on macOS it needs the data protection keychain. Every query must name the attribute (`kSecAttrSynchronizableAny` matches both kinds); an update or delete reaches every device; accessibility must not be `ThisDeviceOnly`. No public API tells whether iCloud Keychain is on (spec updated).
- **Close-up barcodes:** Apple's AVCamBarcode sample picks the virtual back camera (`.builtInTripleCamera`, then `.builtInDualWideCamera`, then `.builtInWideAngleCamera`). It lets it switch constituents (macro on the 16 Pro) and sets `videoZoomFactor` so a 20 mm wide barcode at the device's `minimumFocusDistance` fills the frame. `minimumFocusDistance` is iOS 15+ (`AVCaptureDevice.h:1385`). Source: "AVCamBarcode: detecting barcodes and faces".
- **Photos:** `PhotosPicker` needs no permission; Take Photo needs `UIImagePickerController` (UIKit).
- **Undo gestures** (shake, three-finger swipe) use the scene's `undoManager`, the one `@Environment(\.undoManager)` returns.

## Decisions

1. **An Xcode project with only the iOS target** (`Buchhalter.xcodeproj`, user's choice). It compiles `Sources/Buchhalter/App`, `Sources/Buchhalter/Views` and `iOS/` through synchronized folders and links the package products `BuchhalterCore` and `BuchhalterKeychain`. The Mac stays on SwiftPM and `make`. The doc's `BuchhalterUI` library would make about 60 views `public` and change the Mac build; compiling the files twice costs nothing. The Mac target can join later.
2. **Platform code in three places.** `Mac/` (only in the package's executable), `iOS/` (only in the Xcode target), and shared files that use `#if os(macOS)` / `#if os(iOS)` only for one-line modifiers (`onExitCommand`, `librarySubtitle`, `frame(minWidth:)`, hover-only placeholders). Anything longer than a few lines becomes a modifier with a Mac and an iOS file, like `SyncActionsModifier`.
3. **The `App` struct moves to `Mac/`.** `BuchhalterApp.swift` is Mac-only, so it moves to `Mac/BuchhalterMacApp.swift` unchanged. `iOS/BuchhalterPhoneApp.swift` is the iOS `@main`: a `WindowGroup` with `RootView`, the same container setup without the legacy copy, the schema initializer and `SyncConfiguration`'s Mac checks, plus `BookSources` and `CloudSyncMonitor` as on the Mac.
4. **One `RootView` for every device.** The split view collapses on iPhone (compact width) into Library → list → detail, which is the design's flow. iOS adds the Library screen's bottom bar, the gear, the large titles and the swipe actions through `iOS/PhoneRootChrome.swift` modifiers. The Mac never sees them. The iPhone is limited to portrait in Info.plist; the iPad gets the Mac's layout as is.
5. **`Library.startReading(_:today:)` in the core.** Only a current `wantToRead` reading becomes `reading` with `startedAt` = start of today, as one undo step "Start Reading". Other statuses throw `noWantToRead`; `readAgain` stays for a new reading.
6. **iCloud Keychain as a third keychain mode.** `KeychainSecretStore.Mode` gains `.synchronized(migratingFrom:)`: it reads and writes with `kSecAttrSynchronizable = true`, `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlock` and the access group `3PT9KVM9AJ.de.juergenalbertsen.buchhalter`. The first read that finds nothing reads the non-synchronized data protection item (and, on the Mac, the file-based one) and saves it synchronized. The non-synchronized data protection item is then deleted; the file-based item stays for the CLI. Remove deletes the synchronized item (everywhere) and the local copies. The Mac and iOS apps both use `.synchronized`; the CLI keeps `.fileBased`.
7. **The scan card is its own model over the editor's lookup.** `iOS/Scan/ScanCardModel` (`@Observable`) holds a `BookDraft` with the ISBN and runs a `LookupModel` on it. It exposes the card's state as a value from the core: `ScanCard.Phase` is `looking`, `found(otherEditions:)`, `notFound`, `unreachable` or `duplicate`. "Add and Scan Next" calls `Library.addBook` with the draft and the round's preset. `Edit…` opens `BookEditorSheet` with the prepared draft and result, so no second lookup runs. The Mac's nested Add Book is too much for one hand.
8. **The camera's device choice by platform.** `CameraChoice` gets an iOS rule: back virtual camera first (triple, dual wide, wide), never mirrored. `BarcodeCamera` sets the AVCamBarcode zoom on iOS and adds the torch. Frames still go through `FrameReader` and `ScanSession`, so the confirmation, the amber hint and duplicates are the Mac's (Decision 24 in architecture.md holds).
9. **Background push for sync on iOS:** the `remote-notification` background mode plus `aps-environment` `development`. Without it, a change on the Mac appears on the phone only when the app is brought to the front.
10. **Automatic signing for iOS, manual for the Mac** (user's choice). The Mac keeps its profile; iOS lets Xcode manage the profile that lists jaPhone and the iPad.

## Components

### Core
- `Library.startReading(_:today:)` (`ReadingOperations.swift`) and `LibraryError.noWantToRead` with an English and German message.
- `ScanCard` (`Scan/ScanCard.swift`, new): the phase as a pure function of the lookup's outcome (`LookupOutcome`), the duplicate index and the record list. `otherEditions` counts the editions after the first, using the same matching and order as the edition picker.
- `CameraChoice`: add `iOSBack(available:)` returning the preferred back device kind.

### Keychain
- `KeychainSecretStore.Mode.synchronized(migratingFrom: [Mode])` (Decision 6). `exists()` and `suffix()` stay attribute-only; the comment attribute syncs with the item, so the masked key shows on a new device before the first read.

### Shared views (changed)
- `RootView`: the delete message uses "You can undo it." on iOS and keeps "…with ⌘Z." on the Mac (two catalog keys). `.frame(minWidth:)` becomes Mac-only.
- `BookListView`, `BookGridView`: `swipeActions` (leading: next step; trailing: Delete) on iOS. `startReading` joins `BookContextMenu` (shared) for a Want to Read book. The grid uses three columns at compact width.
- `BookDetailView`, `InlineFields`: on iOS, empty fields show their placeholders always (no hover), and the header stacks vertically at compact width. Long press on the cover adds Choose Photo… and Take Photo… through `CoverPicker` closures.
- `Sidebar/CollectionRow`: `onExitCommand` becomes Mac-only. iOS cancels a rename on submit of an empty name.
- `ScanSheet.swift`: `ScanFeedback` moves to `Views/Sheets/Scan/ScanFeedback.swift`, so iOS can use it without the Mac sheet.
- `BookEditorSheet` and `ScanEditorConfig`: accept a prepared draft and `LookupResult` (the card's `Edit…`).
- `Settings/*Pane`: add a compact form layout used by the iOS settings sheet (rows instead of a bordered fixed-height `List`). The models are unchanged.

### iOS (new, `iOS/`)
- `BuchhalterPhoneApp` (Decision 3). Environment: `\.scanFeedback` = `.phone`, `\.syncActions` from `PhoneSyncActions`.
- `PhoneRootChrome`: the bottom bar (New Collection, Scan, Add), the gear, the iCloud note during a first download, and the "Your library is in iCloud" state (from `SyncState`'s account status).
- `PhoneSettingsView`: a `NavigationStack` with Book Lookup (`EditButton` + `onMove`), Google Books (pushes the key section), iCloud.
- `PhoneSyncActions`: `openAccountSettings` and `openStorageSettings` open `UIApplication.openSettingsURLString`; `showLegacyFolder` is nil (the row hides); `openSyncSettings` opens the settings sheet at iCloud.
- `Scan/ScanScreen`: the full-screen cover with the preview, guide frame, hint, torch, bottom bar and card. Fill mode (from the ISBN field) hides the card and the round.
- `Scan/ScanCardModel` and `Scan/ScanCardView` (Decision 7). `Scan/CameraPreviewView`: `UIViewRepresentable` over `AVCaptureVideoPreviewLayer`, aspect fill, not mirrored.
- `ScanFeedback.phone`: `UINotificationFeedbackGenerator.success` plus `AudioServicesPlaySystemSound(1057)` (silent with the ringer off); `openCameraSettings` opens the app's settings page.
- `CameraCapture`: `UIImagePickerController` for Take Photo…; its image goes through `CoverImage.normalize` as a dropped image does.
- `Info.plist` (camera prompt, `UILaunchScreen`, iPhone portrait only, `remote-notification`, no multiple scenes), `Buchhalter-iOS.entitlements` (the Mac's iCloud, keychain group and `aps-environment` keys, no sandbox keys), `Assets.xcassets` with the 1024 px icon from `Scripts/make-icon.swift`.

## Interactions

**Launch (iOS).** `BuchhalterPhoneApp.init` → `LibraryLocation.storeURL()` (the app's Application Support) → `LibraryContainer.make(at:cloudKitContainer: "iCloud.de.juergenalbertsen.buchhalter")`. A store that did not exist calls `monitor.beginFirstDownload()`. Then `monitor.start()`. A store that cannot open shows an error screen with the path (no quit on iOS) and never deletes the store. `\.bookLookup` and `sources.refreshKey()` work as on the Mac.

**Start Reading.** Row swipe, context menu or Mac menu → `library.startReading(book)` on the main actor → `Library.change` snapshots and registers undo with the scene's `UndoManager` → `@Query` refreshes the lists. A shake shows "Undo Start Reading".

**Scan round.**
1. `ScanScreen` starts `BarcodeCamera` (iOS device choice, zoom).
2. `FrameReader` sends `.detections` to `ScanSession` (main actor).
3. Effect `playSound` calls `scanFeedback.playRead()`; effect `openEditor(isbn)` makes `ScanCardModel(isbn, preset: round.preset)`, pauses the session and starts the lookup.
4. `ScanCard.phase` drives the view.
5. Add and Scan Next calls `library.addBook(draft)` and `round.record`, clears the card and resumes the session. Skip or Scan Another clears and resumes. Show Book ends the round and selects the book (`WindowModel.selectedBookID`, list switched to All Books). Done ends the round.
6. `scenePhase` background stops the camera; active restarts it.

**Key.** Save Key → check (unchanged) → `store.save` (synchronized). Another device: `sources.refreshKey()` at launch and on `scenePhase` active reads `exists()` and `suffix()`, so a key from the Mac shows without typing. Remove → `store.delete()` → gone everywhere after sync.

## Changes by file

| File | | What |
|---|---|---|
| `Buchhalter.xcodeproj` | new | One iOS app target `Buchhalter` (bundle id `de.juergenalbertsen.buchhalter`, iOS 27.0, iPhone and iPad), synchronized folders `Sources/Buchhalter/App`, `Sources/Buchhalter/Views`, `iOS`; package products; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; automatic signing, team `3PT9KVM9AJ`; resources: both catalogs, `PoweredByGoogle.png` |
| `iOS/` | new | The files under Components → iOS |
| `Package.swift` | changed | Library product `BuchhalterKeychain` |
| `Makefile` | changed | `ios` (`xcodebuild -project Buchhalter.xcodeproj -scheme Buchhalter -destination generic/platform=iOS -configuration Release -derivedDataPath build/ios-derived -allowProvisioningUpdates`, copies the app to `build/ios/Buchhalter.app`), `ios-install` (`DEVICE ?= jaPhone`, `xcrun devicectl device install app`), `ios-sim` (simulator build for agents); `make strings` also syncs the `.stringsdata` of an iOS build |
| `Sources/Buchhalter/App/BuchhalterApp.swift` | moved | To `Mac/BuchhalterMacApp.swift`, keychain mode changed |
| `Sources/Buchhalter/Mac/BookCommands.swift` | changed | Start Reading |
| `Sources/Buchhalter/App/BarcodeCamera.swift` | changed | iOS device choice, zoom, torch |
| `Sources/Buchhalter/App/SyncActions.swift` | changed | `showLegacyFolder` optional |
| `Sources/Buchhalter/Views/RootView.swift` | changed | Platform branches (min frame, delete message), hooks for `PhoneRootChrome` |
| `Sources/Buchhalter/Views/Books/BookListView.swift`, `BookGridView.swift`, `BookContextMenu.swift` | changed | Swipe actions, Start Reading, grid columns |
| `Sources/Buchhalter/Views/Detail/BookDetailView.swift`, `InlineFields.swift` | changed | Placeholders without hover, compact header, cover menu |
| `Sources/Buchhalter/Views/Sidebar/CollectionRow.swift` | changed | `onExitCommand` Mac-only |
| `Sources/Buchhalter/Views/Toolbar/LibraryToolbar.swift` | changed | iOS placement (menu with List, Grid, Sort Books…) |
| `Sources/Buchhalter/Views/Sheets/Scan/ScanSheet.swift`, `ScanFeedback.swift` | changed, new | `ScanFeedback` in its own file |
| `Sources/Buchhalter/Views/Sheets/BookEditorSheet.swift` | changed | Prepared draft and result; More group at compact width; Choose and Take Photo |
| `Sources/Buchhalter/Views/Settings/*.swift` | changed | Compact layout; new key note |
| `Sources/BuchhalterKeychain/KeychainSecretStore.swift` | changed | `.synchronized` mode and migration |
| `Sources/BuchhalterCore/Store/ReadingOperations.swift`, `LibraryError.swift` | changed | `startReading`, `noWantToRead` |
| `Sources/BuchhalterCore/Scan/ScanCard.swift`, `CameraChoice.swift` | new, changed | Card phase; iOS back camera rule |
| `Resources/Localizable.xcstrings`, `InfoPlist.xcstrings` | changed | New keys from the spec's table, German values |
| `Tests/BuchhalterCoreTests/ReadingOperationsTests.swift`, `ScanCardTests.swift`, `CameraChoiceTests.swift`, `UndoTests.swift` | changed, new | See Testing |
| `docs/dev/architecture.md`, `AGENTS.md` | changed | Phase 3, targets, layout, decisions, commands |

## Testing

**Unit tests** (`swift test`):
- `startReading`: Want to Read becomes Reading with today's date; it refuses Reading, Finished, Abandoned and no reading; undo and redo restore it (`UndoTests`).
- `ScanCard`: each phase from recorded lookup outcomes (one record, several editions with the right count, none, all sources failed, an ISBN in the duplicate index).
- `CameraChoice` iOS rule: triple before dual wide before wide.
- `LocalizationCatalogTests` covers the new keys.
- `KeychainSecretStore` stays untested, as Decision 21 in architecture.md says.

**Builds** (agent): `make app` (the Mac still builds), `make test`, `make ios-sim` (simulator, no signing) and `make ios` (device build, signs and creates the profile). The agent does not install or run either app.

**Manual checks** (the user, after `make ios-install`, `make ios-install DEVICE=` the iPad's name once it is paired, and `make app`):
1. iPhone: lists and counts match the Mac within a minute. Add a book on the iPhone; it shows on the Mac with its cover, and the other way round.
2. The Google Books key from the Mac shows as saved on the iPhone; Complete uses Google Books; Remove on the iPhone clears it on the Mac after a relaunch.
3. Swipe Start Reading on a Want to Read book, shake to undo. Finish with 4.5 stars; the Mac shows it under Read.
4. Scan five books in a row with a status and a collection on the first. Then scan a known book, a non-ISBN barcode, a book with several editions, and once in flight mode.
5. Deny camera access in Settings, open the scanner, use Open Settings, allow, return.
6. iPad landscape and portrait, `⌘N` with a keyboard, sheets centred.
7. German: set the iPhone to German (or per app: Settings → Buchhalter → Language); on the Mac `open build/Buchhalter.app --args -AppleLanguages '(de)'` shows Lesen beginnen.

## Permissions

| Action | Status | Choice |
|---|---|---|
| `swift build`, `swift test`, `make app`, `make test`, `make strings` | allowed | — |
| `xcodebuild` (inside `make ios`, `make ios-sim`) | allowed | `Bash(xcodebuild:*)` added to `.claude/settings.local.json` |
| `xcodebuild -allowProvisioningUpdates` creating the iOS profile in the developer account | allowed (same rule) | User agreed to automatic signing |
| `make ios-install` / `xcrun devicectl device install` | not run by the agent | The user runs it |
| Launching either app | not run by the agent | The user starts them |

## Risks and open points

- **First compile for iOS:** the shared views have never been built for iOS. Expect more `#if os` fixes; `make ios-sim` finds them.
- **Bundle id:** the iOS app uses the same bundle id as the Mac app (shared keychain group, later universal purchase). After the first automatic signing, check in the developer portal that the App ID still has iCloud with the container.
- **Keychain migration on the Mac is one-way:** after it, the key is in iCloud Keychain and Remove on any device removes it everywhere. The file-based item for the CLI is not touched.
- **Xcode edits the catalog:** an Xcode build with the catalog in the target syncs new keys into `Localizable.xcstrings`. This is wanted; commit the catalog with the code.
- **iPad not paired yet:** the first `make ios` after pairing it registers it in the profile.
