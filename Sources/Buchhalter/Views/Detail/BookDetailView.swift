import SwiftUI
#if os(iOS)
import PhotosUI
#endif
import BuchhalterCore

/// The selected book: large cover, title, status, buttons, collections,
/// readings. Title, subtitle, authors, the meta line and Date Added are
/// edited in place; a book without a cover can look one up from its menu.
struct BookDetailView: View {
    @Environment(\.library) private var library
    @Environment(\.bookLookup) private var bookLookup
    @Environment(BookSources.self) private var sources
    @Environment(\.locale) private var locale
    var model: WindowModel
    var book: Book
    var collections: [Collection]
    /// Language codes already in the library, offered first in the language menus.
    var usedLanguages: [String]

    #if os(iOS)
    /// Touch has no hover: empty fields always show their placeholders, and a
    /// tap on a missing cover shows Find Cover.
    @State private var headerHovered = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var photoItem: PhotosPickerItem?
    @State private var isTakingPhoto = false
    #else
    /// While the pointer is over the header, empty fields show their placeholders.
    @State private var headerHovered = false
    #endif
    @State private var isFindingCover = false
    @State private var coverHovered = false
    @State private var coverTargeted = false

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // An iPhone stacks the cover over the header.
                if isCompact {
                    VStack(alignment: .leading, spacing: 18) {
                        cover
                        header
                    }
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        cover
                        header
                    }
                }
                CollectionChips(model: model, book: book, collections: collections)
                ReadingsSection(model: model, book: book)
            }
            .padding(.horizontal, isCompact ? 20 : 32)
            .padding(.vertical, isCompact ? 16 : 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Cover

    /// A book without a cover shows a Find Cover button and a drop hint over
    /// the generated cover while the pointer is over it or an image is
    /// dragged onto it, so the title on the generated cover stays readable
    /// otherwise.
    private var cover: some View {
        let hasQueries = !LookupQuery.coverQueries(for: BookDraft(book: book)).isEmpty
        let hasSources = sources.hasActiveSource
        let canFind = hasQueries && hasSources
        // The tooltip works on a disabled button.
        let findHelp = hasSources ? "" : String(localized: "Turn on a source in Settings")
        return CoverView(book: book, size: CGSize(width: 120, height: 180))
            .overlay {
                if isFindingCover {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.45))
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    .accessibilityLabel("Finding Cover…")
                } else if book.coverImage == nil, coverHovered || coverTargeted {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.55))
                        if coverTargeted {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                                .padding(4)
                        }
                        VStack(spacing: 8) {
                            if hasQueries {
                                Button("Find Cover") { findCover() }
                                    .buttonStyle(CoverOverlayButtonStyle())
                                    .disabled(!hasSources)
                                    .help(findHelp)
                            }
                            #if os(macOS)
                            Text("or drop an image here")
                                .font(.system(size: 11))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.85))
                            #endif
                        }
                        .padding(8)
                    }
                }
            }
            .onHover { coverHovered = $0 }
            #if os(iOS)
            .onTapGesture { coverHovered.toggle() }
            .onChange(of: photoItem) { _, picked in
                guard let picked else { return }
                Task {
                    if let data = try? await picked.loadTransferable(type: Data.self) { setCover(data) }
                    photoItem = nil
                }
            }
            .fullScreenCover(isPresented: $isTakingPhoto) {
                CameraCapture { data in
                    isTakingPhoto = false
                    if let data { setCover(data) }
                }
                .ignoresSafeArea()
            }
            #endif
            .dropDestination(for: DroppedImage.self) { items, _ in
                guard let data = items.first?.data else { return false }
                setCover(data)
                return true
            } isTargeted: { coverTargeted = $0 }
            .contextMenu {
                #if os(iOS)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose Photo…", systemImage: "photo")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo…", systemImage: "camera") { isTakingPhoto = true }
                }
                #endif
                if book.coverImage != nil {
                    Button("Remove Cover Image") {
                        model.attempt { try library?.setCover(nil, for: book) }
                    }
                } else {
                    Button("Find Cover") { findCover() }
                        .disabled(isFindingCover || !canFind)
                        .help(findHelp)
                }
            }
    }

    /// Asks the sources that are on, in the user's order, with the book's ISBN
    /// and then its title and authors, and sets the first cover found. A cover
    /// set by hand while it runs wins. No cover and no source reached each
    /// have their own alert (`FindCoverAlertModifier`).
    private func findCover() {
        let queries = LookupQuery.coverQueries(for: BookDraft(book: book))
        guard !queries.isEmpty else { return }
        let lookup = bookLookup
        let language = book.language
        isFindingCover = true
        Task {
            defer { isFindingCover = false }
            do {
                guard let data = try await lookup.findCover(queries, preferredLanguage: language) else {
                    model.coverAlert = .noCover(suggestsGoogleBooks: sources.suggestsGoogleBooks)
                    return
                }
                guard book.coverImage == nil else { return }
                model.attempt { try library?.setCover(data, for: book) }
            } catch is LookupError {
                model.coverAlert = .noSourceReached
            } catch {
                // Cancelled: nothing changes.
            }
        }
    }

    // MARK: Header

    private var header: some View {
        let formatting = BookFormatting(locale: locale)
        return VStack(alignment: .leading, spacing: 6) {
            InlineTextField(
                value: book.title, placeholder: "Title", font: Theme.serif(28),
                revealsEmpty: true, fillsWidth: true
            ) { text in save { $0.title = text } }
            InlineTextField(
                value: book.subtitle ?? "", placeholder: "Subtitle", font: .system(size: 15),
                revealsEmpty: headerHovered, fillsWidth: true
            ) { text in save { $0.subtitle = text } }
                .foregroundStyle(.secondary)
            InlineTextField(
                value: book.orderedAuthors.map(\.name).joined(separator: ", "),
                placeholder: "Authors", font: .system(size: 15), revealsEmpty: headerHovered, fillsWidth: true
            ) { text in saveAuthors(text) }
            VStack(alignment: .leading, spacing: 2) {
                metaLine(formatting)
                InlineAddedDate(date: book.addedAt, display: formatting.added(book)) { date in
                    _ = save { $0.addedAt = date }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            if let reading = book.currentReading {
                StatusBadge(reading: reading).padding(.top, 8)
            }
            buttons.padding(.top, 6)
        }
        .onHover { headerHovered = $0 }
    }

    /// "1901 · 759 pages · German · Original: Japanese · Reclam · ISBN 978-…",
    /// each piece editable. Empty pieces appear while the header is hovered.
    private func metaLine(_ formatting: BookFormatting) -> some View {
        let reveal = headerHovered
        let original = book.originalLanguage.flatMap { $0 == book.language ? nil : $0 }
        var pieces: [AnyView] = []
        if book.year != nil || reveal {
            pieces.append(AnyView(InlineTextField(
                value: book.year.map(formatting.year) ?? "", placeholder: "Year", font: .system(size: 12),
                revealsEmpty: true
            ) { text in save { $0.yearText = text } }))
        }
        if book.pageCount != nil || reveal {
            pieces.append(AnyView(InlineTextField(
                value: book.pageCount.map(String.init) ?? "", display: book.pageCount.map(formatting.pageCount),
                placeholder: "Pages", font: .system(size: 12), revealsEmpty: true
            ) { text in save { $0.pagesText = text } }))
        }
        if book.language != nil || reveal {
            pieces.append(AnyView(InlineLanguageMenu(
                code: book.language, display: book.language.map(formatting.languageName) ?? "",
                placeholder: "Language", usedLanguages: usedLanguages, revealsEmpty: true
            ) { code in _ = save { $0.language = code } }))
        }
        if original != nil || reveal {
            let name = original.map(formatting.languageName) ?? ""
            pieces.append(AnyView(InlineLanguageMenu(
                code: original, display: String(localized: "Original: \(name)"),
                placeholder: "Original Language", usedLanguages: usedLanguages, revealsEmpty: true
            ) { code in _ = save { $0.originalLanguage = code } }))
        }
        if book.publisher != nil || reveal {
            pieces.append(AnyView(InlineTextField(
                value: book.publisher ?? "", placeholder: "Publisher", font: .system(size: 12), revealsEmpty: true
            ) { text in save { $0.publisher = text } }))
        }
        let isbn = book.isbnText.map(ISBN.formatted) ?? ""
        if !isbn.isEmpty || reveal {
            pieces.append(AnyView(InlineTextField(
                value: isbn, display: String(localized: "ISBN \(isbn)"), placeholder: "ISBN",
                font: .system(size: 12), revealsEmpty: true
            ) { text in save { $0.isbnText = text } }))
        }
        return FlowLayout(spacing: 0) {
            ForEach(pieces.indices, id: \.self) { index in
                if index > 0 { Text(verbatim: " · ") }
                pieces[index]
            }
        }
    }

    // MARK: Saving

    /// One inline change, one undo step. Returns the library's message for a
    /// value it refuses, which the field shows.
    private func save(_ edit: (inout BookDraft) -> Void) -> String? {
        guard let library else { return nil }
        do {
            try library.updateDetails(of: book, edit)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// "Thomas Mann, Heinrich Mann": names separated by commas. A known
    /// author keeps their sort name; a new one gets the guessed one.
    private func saveAuthors(_ text: String) -> String? {
        guard let library else { return nil }
        let names = text.split(separator: ",").map { AuthorName.normalize(String($0)) }.filter { !$0.isEmpty }
        let drafts = names.map { library.suggestedAuthor(for: $0) }
        return save { $0.authors = drafts }
    }

    @ViewBuilder
    private var buttons: some View {
        #if os(iOS)
        // German labels run longer: when the row does not fit, Finish Reading
        // takes the full width and the other two share the row below.
        ViewThatFits(in: .horizontal) {
            buttonRow
            VStack(alignment: .leading, spacing: 8) {
                if book.status == .reading {
                    Button { model.sheet = .finish(book.id) } label: {
                        Text("Finish Reading…").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    HStack(spacing: 8) {
                        Button { model.sheet = .abandon(book.id) } label: {
                            Text("Abandon").frame(maxWidth: .infinity)
                        }
                        .secondaryAction()
                        Button { model.sheet = .editBook(book.id) } label: {
                            Text("Edit").frame(maxWidth: .infinity)
                        }
                        .secondaryAction()
                    }
                } else {
                    buttonRow
                }
            }
        }
        #else
        buttonRow
        #endif
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            switch book.status {
            case .reading:
                Button("Finish Reading…") { model.sheet = .finish(book.id) }
                    .buttonStyle(.borderedProminent)
                Button("Abandon") { model.sheet = .abandon(book.id) }
                    .secondaryAction()
                Button("Edit") { model.sheet = .editBook(book.id) }
                    .secondaryAction()
            case .finished, .abandoned:
                Button("Read Again") { model.attempt { try library?.readAgain(book) } }
                    .secondaryAction()
                Button("Edit") { model.sheet = .editBook(book.id) }
                    .secondaryAction()
            case .wantToRead:
                Button("Start Reading") { model.attempt { try library?.startReading(book) } }
                    .buttonStyle(.borderedProminent)
                Button("Edit") { model.sheet = .editBook(book.id) }
                    .secondaryAction()
            case nil:
                Button("Edit") { model.sheet = .editBook(book.id) }
                    .secondaryAction()
            }
        }
        .controlSize(.regular)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func setCover(_ data: Data) {
        Task {
            do {
                let normalized = try await CoverImage.normalize(data)
                model.attempt { try library?.setCover(normalized, for: book) }
            } catch {
                model.errorMessage = String(localized: "This image can't be used.")
            }
        }
    }
}

private extension View {
    /// The window's accent tint colours a system bordered button's label, so
    /// dark mode showed dark green text on a dark button. Secondary actions use
    /// their own style with the normal label colour; only the prominent action
    /// is green.
    func secondaryAction() -> some View {
        buttonStyle(SecondaryButtonStyle())
    }
}

/// A neutral bordered button: label in the primary colour, a quiet fill and
/// a hairline border that work in light and dark mode.
private struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    #if os(iOS)
    /// A touch target, as tall as the prominent button next to it.
    static let fontSize: CGFloat = 15
    static let height: CGFloat = 36
    #else
    static let fontSize: CGFloat = 13
    static let height: CGFloat = 24
    #endif

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Self.fontSize))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: Self.height)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.18))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// The Find Cover button over a missing cover: white on the dark scrim, in
/// light and dark mode alike.
private struct CoverOverlayButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.75 : 0.95)))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
    }
}
