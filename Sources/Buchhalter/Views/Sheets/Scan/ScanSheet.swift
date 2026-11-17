import SwiftUI
import BuchhalterCore

/// "Scan Barcode": the live camera picture, a frame on the barcode, and what
/// follows a read. In `addBooks` mode a read opens Add Book over this sheet
/// (nested, so the camera stays warm behind it) and a duplicate shows a banner;
/// in `fillISBN` mode a read hands the ISBN back and closes. The scan logic is
/// `ScanSession` in the core; this view carries out its effects.
struct ScanSheet: View {
    enum Mode {
        case addBooks
        /// Over an open Add Book or Edit Book: the ISBN goes into its field.
        case fillISBN((ISBN) -> Void)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.scanFeedback) private var feedback
    @Environment(\.library) private var library
    var mode: Mode
    var model: WindowModel
    /// Not used in `fillISBN` mode.
    var books: [Book]
    var collections: [Collection]
    /// The scan sheet closed: the book to select, the last one added in the round.
    var onFinished: (UUID?) -> Void = { _ in }
    var onShowBook: (UUID) -> Void = { _ in }
    /// "Type ISBN Instead": the window swaps this sheet for Add Book.
    var onTypeISBN: () -> Void = {}

    /// The books as they are now. The camera's callback and the clock capture
    /// this view once, so `books` itself would be the list at that moment.
    @State private var currentBooks: [Book]
    @State private var camera = BarcodeCamera()
    @State private var session: ScanSession
    @State private var round = ScanRound()
    @State private var imageSize = CGSize.zero
    @State private var pendingEditor: PendingEditor?
    @State private var outcome: EditorOutcome = .cancelled
    @AppStorage("scanInARow") private var inARow = false

    /// Add Book over this sheet, for one scanned ISBN.
    private struct PendingEditor: Identifiable {
        let id = UUID()
        var isbn: ISBN
    }

    private enum EditorOutcome {
        case cancelled, added
        case showBook(UUID)
    }

    init(
        mode: Mode, model: WindowModel, books: [Book], collections: [Collection],
        onFinished: @escaping (UUID?) -> Void = { _ in }, onShowBook: @escaping (UUID) -> Void = { _ in },
        onTypeISBN: @escaping () -> Void = {}
    ) {
        self.mode = mode
        self.model = model
        self.books = books
        self.collections = collections
        self.onFinished = onFinished
        self.onShowBook = onShowBook
        self.onTypeISBN = onTypeISBN
        _currentBooks = State(initialValue: books)
        switch mode {
        case .addBooks: _session = State(initialValue: ScanSession(mode: .addBooks))
        case .fillISBN: _session = State(initialValue: ScanSession(mode: .fillISBN))
        }
    }

    private var isFilling: Bool {
        if case .fillISBN = mode { true } else { false }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Text("Hold the barcode on the back of the book up to the camera. Buchhalter reads the ISBN and looks up the book.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            picture
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 24)
            if case .duplicate(let entry, _) = session.state { duplicateBanner(entry) }
            if !isFilling {
                Text("Tip: an iPhone near this Mac can be the camera (Continuity Camera). A USB barcode scanner works too: scan into the ISBN field of Add Book.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }
            footer
                .padding(.top, 10)
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            camera.onFrame = { detections, size in
                if imageSize != size { imageSize = size }
                apply(.detections(detections, at: .now))
            }
            camera.start()
            await runClock()
        }
        .onDisappear { camera.stop() }
        .onChange(of: books) { _, latest in currentBooks = latest }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.evaluate() }
        }
        .sheet(item: $pendingEditor, onDismiss: editorClosed) { pending in editor(for: pending) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Scan Barcode")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !camera.devices.isEmpty {
                Text("Camera")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Picker("Camera", selection: Binding(
                    get: { camera.selectedID ?? "" }, set: { camera.select($0) }
                )) {
                    ForEach(camera.devices) { device in
                        Text(verbatim: device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
                .fixedSize()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: Picture

    @ViewBuilder
    private var picture: some View {
        let messages = ScanMessages(locale: locale)
        switch camera.state {
        case .running:
            CameraPreview(camera: camera, session: session, imageSize: imageSize)
        case .notDetermined:
            Color(hex: 0x23272B)
        case .denied:
            emptyPanel(title: messages.noAccessTitle(), message: messages.noAccessMessage()) {
                Button("Open System Settings…", action: feedback.openCameraSettings)
                    .controlSize(.small)
            }
        case .noCamera:
            emptyPanel(title: messages.noCameraTitle(), message: messages.noCameraMessage()) {}
        }
    }

    private func emptyPanel<Actions: View>(
        title: String, message: String, @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 8) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.12))
    }

    // MARK: Duplicate

    private func duplicateBanner(_ entry: DuplicateIndex.Entry) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(verbatim: ScanMessages(locale: locale).alreadyInLibrary(entry))
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                Spacer()
                Button("Show Book") {
                    camera.stop()
                    dismiss()
                    onShowBook(entry.bookID)
                }
                Button("Add Anyway") { apply(.addAnyway) }
                Button("Scan Another") { apply(.dismissDuplicate) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if !isFilling {
                    Toggle("Scan several books in a row", isOn: $inARow)
                        .checkboxToggleStyle()
                        .font(.system(size: 12))
                    Spacer()
                    Button("Type ISBN Instead") {
                        camera.stop()
                        onTypeISBN()
                    }
                } else {
                    Spacer()
                }
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    // MARK: Session

    /// Feeds an event to the scan logic and carries out what it asks for.
    private func apply(_ event: ScanSession.Event) {
        // The clock ticks ten times a second: write the session back only when it changed.
        var next = session
        let books = currentBooks
        let effects = next.handle(event) { isbn13 in DuplicateIndex(books: books).match(isbn13: isbn13) }
        if next != session { session = next }
        for effect in effects {
            switch effect {
            case .playSound:
                feedback.playRead()
            case .openEditor(let isbn):
                camera.pause()
                pendingEditor = PendingEditor(isbn: isbn)
            case .fillField(let isbn):
                guard case .fillISBN(let fill) = mode else { break }
                camera.stop()
                dismiss()
                fill(isbn)
            }
        }
    }

    /// The scan logic's clock, and a check for camera access that changed while
    /// the sheet is open (System Settings, a camera plugged in).
    private func runClock() async {
        var ticks = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            apply(.tick(.now))
            ticks += 1
            if ticks % 10 == 0, camera.state != .running, pendingEditor == nil { camera.evaluate() }
        }
    }

    private func cancel() {
        camera.stop()
        dismiss()
        if !isFilling { onFinished(round.lastAddedID) }
    }

    // MARK: Add Book over the scan

    private func editor(for pending: PendingEditor) -> some View {
        BookEditorSheet(
            model: model, editing: nil, books: books, collections: collections,
            onAdded: { _ in }, onShowBook: { id in outcome = .showBook(id) },
            scan: ScanEditorConfig(
                isbn: pending.isbn, round: round, inARow: inARow,
                onSaved: { draft, id in
                    round.recordAdded(draft, id: id)
                    outcome = .added
                }
            )
        )
        .environment(\.library, library)
    }

    /// Add Book closed. A saved book ends the round, or, in a row, goes back to
    /// the camera; Show Book ends it too; Cancel goes back to the camera.
    private func editorClosed() {
        let result = outcome
        outcome = .cancelled
        switch result {
        case .showBook(let id):
            camera.stop()
            dismiss()
            onShowBook(id)
        case .added where !inARow:
            camera.stop()
            dismiss()
            onFinished(round.lastAddedID)
        case .added, .cancelled:
            apply(.resume)
            camera.start()
        }
    }
}
