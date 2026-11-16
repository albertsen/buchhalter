# Barcode Scanning — Plan

## Current State (audited 2026-11-16)

Built on architecture.md (Targets, Data flow, UI structure, Localization). Details that matter here:

- **Sheets:** `RootView` presents `model.sheet` (`ActiveSheet`: `addBook`, `editBook`, …) with `.sheet(item:)` and `sheetContent(_:)`. `BookEditorSheet(model:editing:books:collections:onAdded:onShowBook:)` builds a fresh `BookDraft` for Add Book (default `status` `.wantToRead`, the most used language) and owns a `LookupModel`. `LookupModel.start(_:draft:using:library:)` runs Complete for a `LookupQuery(draft:pendingAuthor:)`. The edition picker already shows a sheet over the editor, so sheet-over-sheet works here.
- **Duplicates:** `DuplicateIndex(books:excluding:)`, `match(for: BookDraft)`. Its label is "Title (Year)", and the editor's banner reads "Already in your library: \(entry.label)" with `Show Book` and `Add Anyway`.
- **ISBN:** `ISBN.parse(_:)` accepts ISBN-10 and ISBN-13 with checksum; `ISBN.hyphenated` uses the range table.
- **Menus and toolbar:** `LibraryCommands` replaces `.newItem` with `Add Book…` (⌘N), so it sits in the File menu, not a Library menu. `LibraryToolbar` has the `plus` button (`.primaryAction`, `onAdd`).
- **Bundle:** `Resources/Info.plist` has no `NSCameraUsageDescription` and no `InfoPlist` strings. `make app` compiles only `Localizable.xcstrings`. The app is ad-hoc signed, without hardened runtime or sandbox, so the camera needs no entitlement today.
- **Corrections to the spec, made in this plan's commit:**
  - The duplicate banner uses the existing label: "Already in your library: Buddenbrooks (1901)", the same as in Add Book.
  - A new round starts with Add Book's usual defaults (status Want to Read), not an empty status.

## Research

Checked against the installed macOS 27.2 SDK (Xcode 27.2) on 2026-11-16.

- **Barcode reading:** Vision's Swift API `DetectBarcodesRequest` (macOS 15, iOS 18) reads EAN-13 from video frames and returns the payload and a normalized bounding box (origin bottom left) in the image's own orientation. `AVCaptureMetadataOutput` exists on macOS 13+, but `rectOfInterest` is iOS-only, and Vision is the path that works the same on both platforms. ([DetectBarcodesRequest](https://developer.apple.com/documentation/vision/detectbarcodesrequest); SDK: `Vision.swiftmodule/arm64e-apple-macos.swiftinterface`, line 940)
- **Cameras:** `AVCaptureDevice.DiscoverySession` with `.builtInWideAngleCamera`, `.continuityCamera` and `.external` (macOS 14). `.continuityCamera` needs `NSCameraUseContinuityCameraDeviceType` = true in Info.plist (`AVCaptureDevice.h`, line 659). `isContinuityCamera` and `systemPreferredCamera` exist since macOS 13.
- **Mirroring:** `AVCaptureConnection.automaticallyAdjustsVideoMirroring` is iOS-only (`AVCaptureSession.h`, line 1062). On macOS, set `isVideoMirrored` on the preview layer's connection when `isVideoMirroringSupported`. The video data output stays unmirrored, so Vision sees the real image.
- **Permission:** `AVCaptureDevice.authorizationStatus(for: .video)` and `requestAccess(for:)`. The prompt shows `NSCameraUsageDescription`, which is localized through `InfoPlist.strings` in each `.lproj`. TCC keys an ad-hoc signed app by its code hash, so each `make app` asks again. Proper signing (icloud-sync) ends that.
- **Sandbox, later:** once icloud-sync turns on the sandbox and hardened runtime, the camera needs `com.apple.security.device.camera`. This plan adds it to that plan's entitlements list.
- **Privacy page:** `x-apple.systempreferences:com.apple.preference.security?Privacy_Camera`. The implementer checks that macOS 27 opens Camera with it.

## Decisions

1. **Vision on frames from `AVCaptureVideoDataOutput`,** not `AVCaptureMetadataOutput` and not VisionKit. VisionKit's `DataScannerViewController` is iOS-only. Vision runs on both platforms, so the iOS app can reuse the frame reader with its own preview. Whether iOS uses DataScanner instead is decided in its own spec.
2. **The scan logic is pure and lives in core** (`BarcodeReading`, `ScanSession`, `ScanRound`, `ScanGeometry`), with no AVFoundation or Vision. The camera side only delivers payloads with boxes and timestamps. This follows architecture.md, Decision 4. Everything that decides what the user sees is unit-tested.
3. **A read counts after two matching frames within 0.5 s.** Single-frame misreads of EAN-13 happen with blurry built-in cameras. One more frame at 30 fps costs nothing noticeable.
4. **The scan sheet hosts Add Book as a nested sheet** (the spec's stacked sheets). `ActiveSheet.scanBarcode` opens `ScanSheet`, which presents `BookEditorSheet` from its own `.sheet`. The camera session pauses while Add Book is up and resumes on dismiss, so the next book needs no camera start.
5. **`BookEditorSheet` takes a scan configuration** instead of a second editor: an initial ISBN, whether to start Complete at once, and the round (preset, count, main button title). Add Book stays one sheet, one draft, as architecture.md describes.
6. **Scanning into a field is a mode of `ScanSheet`** (`.fillISBN`), presented over the editor from the ISBN field's button. It calls back with the ISBN and closes, with no duplicate banner and no round.
7. **Camera choice:** with nothing stored, a Continuity Camera device if one is connected, else `systemPreferredCamera`. The user's choice is stored as the device's `uniqueID` in UserDefaults (`scanCamera`), per Mac like other view state. When the stored device is gone, fall back to the built-in camera without overwriting the stored id, so the iPhone is picked again when it comes back.
8. **The sound is `NSSound(named: "Tink")`,** played through an environment closure (`\.scanFeedback`) the Mac app sets. The shared view stays free of AppKit, and iOS later supplies a haptic.
9. **`InfoPlist.xcstrings`** joins `Resources/` for the usage description, compiled by `make app` like the main catalog. The catalog test checks it too.

## Components

### Core (`Sources/BuchhalterCore/Scan/`)

- **`BarcodeReading`:** `classify(_ payload: String) -> Reading`, with `Reading` being `.isbn(ISBN)`, `.notISBN(display: String)` or `.ignored`. Only 13 digits count. 978 or 979 with a valid check digit gives `.isbn`. Other valid EAN-13 gives `.notISBN`, displayed EAN-style ("4 006381 333931"). A wrong checksum, other lengths or letters give `.ignored`. ISBN-10 is never accepted here (spec non-goal), unlike `ISBN.parse`.
- **`ScanSession`:** a value-type state machine, `mutating func handle(_ event: Event) -> Effect?`. Events: `.detections([Detection], at: Date)` (a detection is a payload and a normalized box), `.tick(Date)`, `.pause`, `.resume`, `.dismissDuplicate`. State: `.looking`, `.confirming(payload, since)`, `.found(ISBN, box)`, `.hint(display, box, until)`, `.duplicate(DuplicateIndex.Entry)`, `.paused`. Effects: `.playSound`, `.openEditor(ISBN)` (0.5 s after `.found`), `.fillField(ISBN)`. It takes a duplicate lookup closure `(String) -> DuplicateIndex.Entry?`, `nil` in `.fillISBN` mode. Hints last 4 s and give way to the next barcode. The same non-ISBN code read again while its hint shows does not restart the timer.
- **`ScanRound`:** `count`, `preset: (status: DraftStatus?, collectionIDs: [UUID])?`, `lastAddedID`. `mutating func recordAdded(_ draft: BookDraft, id: UUID)` stores the preset and counts. `func apply(to draft: inout BookDraft)` sets the status (with the default dates for Reading or Read, as when the user picks them) and the collections.
- **`ScanGeometry`:** `overlayRect(normalizedBox:imageSize:viewSize:mirrored:) -> CGRect`. It flips the y axis (Vision is bottom-left), mirrors x when the preview is mirrored, and maps aspect-fill into view points. Pure math, tested.
- **`DuplicateIndex.match(isbn13:)`:** new, the ISBN half of `match(for:)`.
- **`ScanMessages`:** the hint, banner and empty-state texts (English keys, German in the catalog), like `LookupMessages`.

### App, shared (AVFoundation and Vision only, iOS-ready)

- **`BarcodeCamera`** (`App/`, `@Observable @MainActor`): devices, the selected device, the authorization state (`notDetermined`, `denied`, `noCamera`, `running`), `start()`, `pause()`, `stop()`. It owns the `AVCaptureSession` and runs `startRunning` and `stopRunning` on its own serial queue. It observes `AVCaptureDevice.wasConnected` and `wasDisconnected` and re-checks authorization when the app becomes active. It forwards detections to the main actor.
- **`FrameReader`** (`nonisolated final class`, the sample buffer delegate on the capture queue): runs `DetectBarcodesRequest` with symbology `.ean13` on at most 10 frames a second and drops frames while one is in flight. It sends `[Detection]` and the image size to `BarcodeCamera` through an `AsyncStream`. It never retains sample buffers and never writes or uploads images.
- **`ScanSheet`** (`Views/Sheets/Scan/`): modes `.addBooks` and `.fillISBN(onISBN:)`.
  - It holds `BarcodeCamera`, `ScanSession` and `ScanRound`, and the checkbox as `@AppStorage("scanInARow")`.
  - It shows the header with the camera picker, the preview (`CameraPreview`) with the overlay frame from `ScanGeometry`, the status capsule, the duplicate banner, the empty states and the footer.
  - A 0.25 s timer drives `.tick`. Effects map to the sound, to presenting `BookEditorSheet` (nested `.sheet`) and to `onISBN`.
- **`CameraPreview`:** a protocol-free view that takes the session. Its platform bridge is Mac-only (below).
- **`BookEditorSheet`** (changed):
  - A new optional `scan: ScanEditorConfig`: `initialISBN`, `autoComplete`, `round: ScanRound?`, `inARow: Bool`, `onCancel`.
  - In `init`, the ISBN goes into the draft and the round's preset is applied. On appear with `autoComplete`, it starts `LookupModel` with `LookupQuery(draft:pendingAuthor:)`.
  - With `inARow`, the primary button reads `Add and Scan Next`, and the footer shows "Added in this round: N" for N > 0.
  - A barcode button right of the ISBN field (`barcode.viewfinder`, help "Scan Barcode") presents `ScanSheet(.fillISBN)`. On an ISBN it sets `draft.isbnText` to the hyphenated form and, when adding, starts Complete.
- **`RootView`:** `case .scanBarcode` in `sheetContent`. `ScanSheet` gets `books`, `collections`, `library`, and `onFinished(lastAddedID)` / `onShowBook`, both through `reveal(_:)`.
- **`WindowModel.ActiveSheet`:** `.scanBarcode`.
- **`LibraryToolbar`:** a `Scan Barcode` item (`barcode.viewfinder`) before `Add Book`, calling `onScan`.

### Mac-only

- **`LibraryCommands`:** `Scan Barcode…` after `Add Book…`, ⇧⌘N, sets `model.sheet = .scanBarcode`.
- **`CameraPreviewLayer`** (`Mac/`): an `NSViewRepresentable` hosting `AVCaptureVideoPreviewLayer`, `videoGravity` `.resizeAspectFill`, connection `isVideoMirrored = true` when supported. It reports the layer size for `ScanGeometry`.
- **`ScanFeedback`:** sets `\.scanFeedback` to play "Tink", and opens the camera privacy page for `Open System Settings…`.

### Resources and build

- `Info.plist`: `NSCameraUsageDescription` (English) and `NSCameraUseContinuityCameraDeviceType` true.
- `Resources/InfoPlist.xcstrings`: the usage description in English and German, from the spec.
- `Makefile` `app`: also `xcstringstool compile Resources/InfoPlist.xcstrings` into `Contents/Resources`. The implementer checks that it yields `{en,de}.lproj/InfoPlist.strings`.

## Interactions

**Scan one or more books:**

```
⇧⌘N / toolbar → model.sheet = .scanBarcode → ScanSheet(.addBooks) appears
  BarcodeCamera.start(): authorization → requestAccess if needed → session on capture queue
  FrameReader (capture queue) → Vision → [Detection] → AsyncStream → main actor
  ScanSession.handle(.detections) → .confirming → second match → .found
      effect .playSound → \.scanFeedback; overlay green via ScanGeometry
      0.5 s tick → effect .openEditor(isbn)
        duplicate? → state .duplicate → banner (Show Book | Add Anyway | Scan Another)
  ScanSheet: camera.pause(); present BookEditorSheet(scan: initialISBN, autoComplete, round)
      Complete runs as today (LookupModel); the user saves
      Add → Library.addBook (one undo step) → round.recordAdded → dismiss
         inARow: session.resume, camera.start → looking
         else:   ScanSheet dismisses → onFinished(id) → reveal(id)
      Cancel → dismiss → resume → looking
  Cancel / Esc in ScanSheet → camera.stop() → onFinished(round.lastAddedID)
```

The camera stops in `onDisappear` in every path, so the camera light goes off.

**Fill the ISBN field:** editor's barcode button → `ScanSheet(.fillISBN)` → `.found` → `.playSound`, `.fillField(isbn)` → `onISBN(isbn)` → the sheet dismisses → the editor sets the field and starts Complete (Add Book only).

**Permission changes:** the app becomes active → `BarcodeCamera` re-reads `authorizationStatus` → `.running` starts the preview without reopening the sheet.

## Changes by file

| File | | Change |
|---|---|---|
| `Sources/BuchhalterCore/Scan/BarcodeReading.swift` | new | EAN-13 classification |
| `Sources/BuchhalterCore/Scan/ScanSession.swift` | new | state machine, effects, timings |
| `Sources/BuchhalterCore/Scan/ScanRound.swift` | new | count, preset, last added |
| `Sources/BuchhalterCore/Scan/ScanGeometry.swift` | new | box → overlay rect, mirroring |
| `Sources/BuchhalterCore/Scan/ScanMessages.swift` | new | texts |
| `Sources/BuchhalterCore/Logic/DuplicateIndex.swift` | changed | `match(isbn13:)` |
| `Sources/Buchhalter/App/BarcodeCamera.swift` | new | session, devices, authorization |
| `Sources/Buchhalter/App/FrameReader.swift` | new | Vision on frames, off the main actor |
| `Sources/Buchhalter/App/WindowModel.swift` | changed | `ActiveSheet.scanBarcode` |
| `Sources/Buchhalter/Views/Sheets/Scan/ScanSheet.swift` | new | the scan sheet |
| `Sources/Buchhalter/Views/Sheets/Scan/CameraPreview.swift` | new | shared wrapper, overlay |
| `Sources/Buchhalter/Views/Sheets/BookEditorSheet.swift` | changed | scan config, barcode button, round footer |
| `Sources/Buchhalter/Views/RootView.swift` | changed | present `ScanSheet` |
| `Sources/Buchhalter/Views/Toolbar/LibraryToolbar.swift` | changed | scan button |
| `Sources/Buchhalter/Mac/LibraryCommands.swift` | changed | `Scan Barcode…` ⇧⌘N |
| `Sources/Buchhalter/Mac/CameraPreviewLayer.swift` | new | mirrored preview layer |
| `Sources/Buchhalter/Mac/ScanFeedback.swift` | new | sound, privacy page |
| `Resources/Info.plist` | changed | camera keys |
| `Resources/InfoPlist.xcstrings` | new | usage description en and de |
| `Resources/Localizable.xcstrings` | changed | all new texts |
| `Makefile` | changed | compile `InfoPlist.xcstrings` |
| `Tests/BuchhalterCoreTests/…` | new | see Testing |
| `specs/planned/barcode-scanning/spec.md` | changed | duplicate label, round defaults (see Current State) |
| `specs/planned/icloud-sync/plan.md` | changed | add `com.apple.security.device.camera` |

## Testing

Unit tests (`swift test`):

- `BarcodeReadingTests`:
  - 9783596294312 → ISBN, hyphenated 978-3-596-29431-2. A 979 ISBN → ISBN.
  - 4006381333931 → not an ISBN, displayed "4 006381 333931".
  - A 978 code with a wrong check digit → ignored. 12-digit UPC, an ISBN-10 string, letters → ignored.
- `ScanSessionTests`:
  - One frame never confirms; two within 0.5 s do; two 0.6 s apart don't.
  - The sound fires once per read. The editor opens 0.5 s after the read.
  - The hint expires after 4 s, and the same code doesn't restart it.
  - A duplicate gives the banner, not the editor. Scan Another returns to looking.
  - In fill mode: no duplicate check, `.fillField` at once.
  - Pause ignores detections; resume clears the last code, so the same book can be scanned again.
- `ScanRoundTests`: the preset from the first book applies to the second, a change on the second carries to the third, the count increases, and a fresh round has no preset.
- `ScanGeometryTests`: a centered box stays centered. A box at the image's left lands at the view's right when mirrored. The y flip and the aspect-fill crop are correct for a 1920 × 1080 image in a 512 × 330 view.
- `DuplicateIndexTests`: `match(isbn13:)`.
- `LocalizationCatalogTests`: extended to `InfoPlist.xcstrings` and the spec's German terms.

Build: `make test`, `make strings`, `make app`.

Manual checks (the user, real library). Each new `make app` asks for camera access again until icloud-sync signs the app.

1. ⇧⌘N, `File → Scan Barcode…` and the toolbar button open the sheet. The camera access prompt shows the spec's text. After allowing, the picture appears, mirrored: the book moves to the side of the hand.
2. With an iPhone as the camera, Buddenbrooks (978-3-596-29431-2): sound, green frame, "ISBN 978-3-596-29431-2", Add Book with Complete running.
3. The same with the built-in camera at 30 to 40 cm.
4. A price barcode on a book or another product: amber hint for about 4 s.
5. A book already in the library: the banner. Show Book selects it; Scan Another looks again.
6. Checkbox on, three books: `Add and Scan Next` each time, "Added in this round: 2" before the third, the status and collection of the first preset for the others. `Cancel` in the scan sheet selects the last one.
7. Checkbox off: `Add Book` closes both and selects the book.
8. The barcode button in Add Book and in Edit Book fills the ISBN; only Add Book starts Complete.
9. Deny camera access in System Settings, open the scanner: the message, and `Open System Settings…` opens Camera. Allowing starts the picture without reopening.
10. Close the sheet: the camera light goes off.
11. German: `open build/Buchhalter.app --args -AppleLanguages '(de)'`, then the menu item, sheet, hints, banner, footer and the access prompt (reset it with `tccutil reset Camera local.buchhalter` to see the prompt again).

## Permissions

| Action | Status |
|---|---|
| `swift build`, `swift test`, `make test`, `make strings`, `make app` | allowed (`.claude/settings.json`) |
| Starting the app, granting camera access, `tccutil reset Camera local.buchhalter` | the user does it |

## Risks and open points

- **Camera prompt per build:** the ad-hoc signature changes with every build, so TCC asks again each time. This is expected until icloud-sync, not a bug.
- **Built-in camera focus:** Vision may not read a barcode at the distance the fixed focus needs. Goal 4 of the spec allows for this. If 1080p cameras fail, give the user the numbers rather than tuning in circles.
- **Vision on many frames:** limit to 10 frames a second and one request in flight. Watch the CPU in Activity Monitor during check 2.
- **Nested sheets:** a `.sheet` inside a sheet that is itself inside `RootView`'s `.sheet(item:)`. The edition picker proves one level works over the editor. Here it's scan → editor → edition picker, three levels. Check that dismissing the editor leaves the scan sheet in place.
- **Swift 6 isolation:** the app target is `@MainActor` by default. `FrameReader` and the capture queue code must be explicitly `nonisolated`, with values crossing to the main actor through the stream only.
- **`Return` in a USB scanner flow:** the editor's primary button is the default action. With `inARow` its title changes but it stays the default, so a USB scanner's `Return` adds the book.
- **Left to the implementer:** the overlay's corner style and animation, the capsule styling within the design, and whether `CameraPreview` and the overlay are one view or two.
