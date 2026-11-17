import SwiftUI
import UIKit
import BuchhalterCore

// iOS-only: the scanner on iPhone and iPad. The Mac's is ScanSheet; both run
// the same ScanSession, so reads, hints and duplicates follow the same rules.

/// The full-screen camera. In `addBooks` mode every read is part of a round:
/// a card over the camera shows the book found, and Add and Scan Next adds it
/// and looks for the next barcode. In `fillISBN` mode a read hands the ISBN
/// back and closes.
struct ScanScreen: View {
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
    @Environment(\.bookLookup) private var bookLookup
    var mode: Mode
    var model: WindowModel
    var books: [Book]
    var collections: [Collection]
    var onShowBook: (UUID) -> Void = { _ in }
    var onTypeISBN: () -> Void = {}
    var onDone: () -> Void = {}

    @State private var currentBooks: [Book]
    @State private var camera = BarcodeCamera()
    @State private var session: ScanSession
    @State private var round = ScanRound()
    @State private var imageSize = CGSize.zero
    @State private var card: ScanCardModel?
    @State private var torchOn = false
    @State private var editing: EditorRequest?
    @State private var showsEditions = false
    @State private var choosesCollections = false

    private struct EditorRequest: Identifiable {
        let id = UUID()
        var isbn: ISBN
        var prepared: PreparedDraft
    }

    init(
        mode: Mode, model: WindowModel, books: [Book], collections: [Collection],
        onShowBook: @escaping (UUID) -> Void = { _ in }, onTypeISBN: @escaping () -> Void = {},
        onDone: @escaping () -> Void = {}
    ) {
        self.mode = mode
        self.model = model
        self.books = books
        self.collections = collections
        self.onShowBook = onShowBook
        self.onTypeISBN = onTypeISBN
        self.onDone = onDone
        _currentBooks = State(initialValue: books)
        switch mode {
        case .addBooks: _session = State(initialValue: ScanSession(mode: .addBooks))
        case .fillISBN: _session = State(initialValue: ScanSession(mode: .fillISBN))
        }
    }

    private var isFilling: Bool {
        if case .fillISBN = mode { true } else { false }
    }

    private var messages: ScanMessages { ScanMessages(locale: locale) }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            picture.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottom
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task {
            camera.onFrame = { detections, size in
                if imageSize != size { imageSize = size }
                apply(.detections(detections, at: .now))
            }
            camera.setRotation(currentAngle)
            camera.start()
            await runClock()
        }
        .onDisappear {
            card?.stop()
            camera.stop()
        }
        .onChange(of: books) { _, latest in currentBooks = latest }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if card == nil, editing == nil { camera.start() } else { camera.evaluate() }
            case .background:
                torchOn = false
                camera.pause()
            default:
                break
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in camera.setRotation(currentAngle) }
        .sheet(item: $editing, onDismiss: resume) { request in editor(for: request) }
        .sheet(isPresented: $showsEditions) { editionPicker }
        .sheet(isPresented: $choosesCollections) { collectionPicker }
    }

    private var currentAngle: CGFloat {
        CameraRotation.angle(for: UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    }

    // MARK: Picture

    @ViewBuilder
    private var picture: some View {
        switch camera.state {
        case .running:
            CameraPreview(camera: camera, session: session, imageSize: imageSize)
        case .notDetermined:
            Color(hex: 0x23272B)
        case .denied:
            VStack(spacing: 12) {
                Image(systemName: "video.slash")
                    .font(.system(size: 40, weight: .light))
                Text(verbatim: messages.noAccessTitle())
                    .font(.title3.weight(.semibold))
                Text(verbatim: messages.noAccessMessagePhone())
                    .foregroundStyle(.secondary)
                Button("Open Settings", action: feedback.openCameraSettings)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)
                if !isFilling {
                    Button("Type ISBN Instead") {
                        stopCamera()
                        onTypeISBN()
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(32)
        case .noCamera:
            VStack(spacing: 12) {
                Text(verbatim: messages.noCameraTitle()).font(.title3.weight(.semibold))
            }
        }
    }

    // MARK: Top and bottom

    private var topBar: some View {
        HStack {
            Button("Cancel", action: finish)
                .buttonStyle(.bordered)
            Spacer()
            if camera.state == .running {
                Button {
                    torchOn.toggle()
                    camera.setTorch(torchOn)
                } label: {
                    Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Torch")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var bottom: some View {
        if let card {
            ScanCardView(
                card: card, collections: collections,
                onAdd: { add(card) },
                onEdit: { edit(card) },
                onSkip: { closeCard() },
                onRetry: { if let library { card.start(using: bookLookup, library: library) } },
                onEditions: { showsEditions = true },
                onCollections: { choosesCollections = true }
            )
        } else if case .duplicate(let entry, _) = session.state {
            duplicateCard(entry)
        } else if !isFilling {
            VStack(alignment: .leading, spacing: 12) {
                if round.count > 0 {
                    Text(verbatim: messages.addedInRound(round.count))
                        .font(.footnote)
                }
                Button(action: finish) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.6))
        }
    }

    private func duplicateCard(_ entry: DuplicateIndex.Entry) -> some View {
        let book = currentBooks.first { $0.id == entry.bookID }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if let book { CoverView(book: book, size: CGSize(width: 48, height: 72)) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: messages.alreadyInLibraryHeading())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(verbatim: entry.label)
                        .font(.system(.headline, design: .serif))
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                Button {
                    stopCamera()
                    onShowBook(entry.bookID)
                } label: {
                    Text("Show Book").frame(maxWidth: .infinity)
                }
                Button {
                    apply(.addAnyway)
                } label: {
                    Text("Add Anyway").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            Button {
                apply(.dismissDuplicate)
            } label: {
                Text("Scan Another").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .cardBackground()
    }

    // MARK: Session

    private func apply(_ event: ScanSession.Event) {
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
                openCard(for: isbn)
            case .fillField(let isbn):
                guard case .fillISBN(let fill) = mode else { break }
                stopCamera()
                dismiss()
                fill(isbn)
            }
        }
    }

    private func runClock() async {
        var ticks = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            apply(.tick(.now))
            ticks += 1
            if ticks % 10 == 0, camera.state != .running, card == nil { camera.evaluate() }
        }
    }

    // MARK: Card

    private func openCard(for isbn: ISBN) {
        guard let library else { return }
        let language = LanguageOptions.defaultLanguage(books: currentBooks)
        let model = ScanCardModel(isbn: isbn, round: round, language: language, firstSource: bookLookup.sources.first ?? .dnb)
        card = model
        model.start(using: bookLookup, library: library)
    }

    private func add(_ card: ScanCardModel) {
        guard let library else { return }
        model.attempt {
            let book = try card.add(using: library)
            round.recordAdded(card.draft, id: book.id)
            closeCard()
        }
    }

    private func edit(_ card: ScanCardModel) {
        card.stop()
        editing = EditorRequest(isbn: card.card.isbn, prepared: PreparedDraft(draft: card.draft, result: card.result))
    }

    /// Skip, Scan Another after a card, or a book added: back to the camera.
    private func closeCard() {
        card?.stop()
        card = nil
        resume()
    }

    private func resume() {
        guard card == nil || editing == nil else { return }
        apply(.resume)
        camera.start()
    }

    private func editor(for request: EditorRequest) -> some View {
        BookEditorSheet(
            model: model, editing: nil, books: currentBooks, collections: collections,
            onAdded: { _ in }, onShowBook: { id in
                stopCamera()
                onShowBook(id)
            },
            scan: ScanEditorConfig(
                isbn: request.isbn, round: round, inARow: true,
                onSaved: { draft, id in
                    round.recordAdded(draft, id: id)
                    card?.stop()
                    card = nil
                },
                prepared: request.prepared
            )
        )
        .environment(\.library, library)
    }

    @ViewBuilder
    private var editionPicker: some View {
        if let card, let list = card.card.editionList {
            EditionPickerSheet(
                list: list, query: .isbn(card.card.isbn, display: card.card.isbn.hyphenated),
                use: { record in
                    showsEditions = false
                    if let library { card.choose(record, using: bookLookup, library: library) }
                },
                cancel: { showsEditions = false }
            )
        }
    }

    @ViewBuilder
    private var collectionPicker: some View {
        if let card {
            NavigationStack {
                List(collections) { collection in
                    let isOn = card.draft.collectionIDs.contains(collection.id)
                    Button {
                        if isOn {
                            card.draft.collectionIDs.removeAll { $0 == collection.id }
                        } else {
                            card.draft.collectionIDs.append(collection.id)
                        }
                    } label: {
                        HStack {
                            Text(verbatim: collection.name).foregroundStyle(.primary)
                            Spacer()
                            if isOn { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                }
                .navigationTitle("Collections")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { choosesCollections = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: End

    private func stopCamera() {
        torchOn = false
        card?.stop()
        camera.stop()
    }

    /// Done or Cancel: the round ends, the books added stay.
    private func finish() {
        stopCamera()
        if isFilling { dismiss() } else { onDone() }
    }
}

extension View {
    /// The light card over the lower part of the camera.
    func cardBackground() -> some View {
        padding(20)
            .padding(.bottom, 12)
            .frame(maxWidth: 600)
            .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
            .environment(\.colorScheme, .light)
    }
}
