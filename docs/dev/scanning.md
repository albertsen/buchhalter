# Barcode scanning

Add a book by holding the EAN-13 barcode on its back, its ISBN-13, up to a camera: the Mac's camera (or an iPhone as Continuity Camera), or the back camera of the iPhone and iPad. A USB or Bluetooth scanner types into the ISBN field like a keyboard. Overview: [architecture.md](architecture.md).

## Reading

Vision's `DetectBarcodesRequest` (`.ean13`) on the frames of an `AVCaptureVideoDataOutput`, in `FrameReader` on the capture queue: at most 10 frames a second, one in flight. Only the payload, the box and the image size leave it, through an `AsyncStream`; no image is stored or sent.

## Core

All unit-tested without a camera:

- `BarcodeReading`: 978 or 979 with a valid check digit is an ISBN; another valid EAN-13 shows as "4 006381 333931" with the amber hint. ISBN-10 is not accepted.
- `ScanSession`: a value-type state machine, events in (detections, ticks, resume), effects out (sound, open the editor or card 0.5 s after the read, fill a field). A read counts after two frames with the same payload within 0.5 s. A known ISBN (`DuplicateIndex.match(isbn13:)`) gives the duplicate state instead.
- `ScanRound`: the count, the status and collections of the last book as the next one's preset, the last added.
- `ScanCard` (iOS): the card's phase (looking at a source, found with the other editions counted, not found, unreachable), retry and edition choice.
- `ScanGeometry` maps the box into the picture; `CameraChoice` picks the camera; `ScanMessages` holds the texts.

## Camera

`BarcodeCamera` (`@Observable`, shared) owns a `CaptureController` that runs every `AVCaptureSession` call on one serial queue, tracks access (`notDetermined`, `denied`, `noCamera`, `running`), and re-reads access on a timer while the picture is not running. It stops the session in every path, so the camera light goes off.

- **Mac:** an iPhone first when nothing is stored, the built-in camera when the stored one is away (`scanCamera`). It watches cameras connecting and disconnecting. `NSCameraUseContinuityCameraDeviceType` makes an iPhone show up. Only the preview layer is mirrored (`CameraPreviewLayer`); Vision reads the unmirrored frames. The app has `com.apple.security.device.camera`.
- **iOS:** the triple, then the dual wide, then the wide back camera (`CameraChoice.backCamera`). Autofocus is restricted to near, and the zoom follows Apple's AVCamBarcode rule: zoomed until a 37 mm EAN-13 at the closest sharp distance fills the guide frame. `videoRotationAngle` follows the interface orientation; the torch can be switched. Not mirrored.

The read sound is `\.scanFeedback`: "Tink" on the Mac, a success haptic and system sound 1057 on iOS.

## Mac flow

`ScanSheet` (⇧⌘N, the toolbar button, File → Scan Barcode…) shows the picture with a guide frame, a frame on the barcode (green for an ISBN, amber otherwise) and a status capsule, then the duplicate banner, the tip and the footer ("Scan several books in a row", Type ISBN Instead, Cancel). A read pauses the camera and opens Add Book as a nested sheet (`BookEditorSheet` with a `ScanEditorConfig`: the ISBN, Complete at once, the round's preset, "Add and Scan Next", "Added in this round: N"). Closing it resumes the camera, or ends the round (checkbox off, Show Book).

## iOS flow

`ScanScreen` is a full-screen cover with the camera, Cancel, the torch and Done with "Added in this round: N". Every scan is a round. A read pauses the camera and shows the card (`ScanCardModel` runs a `LookupModel` on a draft with the round's preset; `ScanCardView`): the best match with its source, "N other editions" (opens the edition picker), the status segments, a Collections line, Edit… and Add and Scan Next. Edit… opens `BookEditorSheet` with the card's draft and lookup result (`ScanEditorConfig.prepared`), so nothing is looked up twice. The card fetches the synopsis with the cover (lookup.md, Synopsis) but does not show it; Add and Scan Next saves it. A known ISBN shows the duplicate card (Show Book, Add Anyway, Scan Another). The scene going to the background stops the camera.

On both platforms the barcode button next to the ISBN field opens the scanner in `fillISBN` mode, which puts the read ISBN into the field and closes.

## Decisions

- **Scan logic in the core, the camera at the edge.** Confirmation, hints, duplicates, rounds and pausing are tested without AVFoundation or Vision.
- **Vision on video frames, not `AVCaptureMetadataOutput` or VisionKit.** The same code runs on macOS and iOS and reports the box in image coordinates; the alternatives are iOS-only.
- **On the Mac, Add Book as a nested sheet.** Add Book stays one sheet with one draft; the camera pauses under it and resumes on dismiss.
- **On iOS, a card instead of the editor.** On a phone held in one hand, a card with Add and Scan Next is quicker than a full editor; Edit… is one tap away.
