import SwiftUI
#if os(iOS)
import UIKit
#endif
import BuchhalterCore

/// What a barcode scan adds to Add Book: the ISBN that was read (Complete
/// starts at once), the round's earlier books (their status and collections
/// are preset, and their count shows in the footer) and whether the round
/// goes on after this book.
struct ScanEditorConfig {
    var isbn: ISBN
    var round: ScanRound
    var inARow: Bool
    /// Called with the saved draft and the new book's id.
    var onSaved: (BookDraft, UUID) -> Void
    /// The iOS scan card's book, already looked up and merged: the editor
    /// starts from it and runs no second lookup.
    var prepared: PreparedDraft?
}

/// A draft the scan card filled in, with what the lookup did to it (the
/// banner, highlights and notes).
struct PreparedDraft {
    var draft: BookDraft
    var result: LookupResult?
}

/// Add Book and Edit Book: one sheet, one `BookDraft`, validated while the
/// user types. The store applies the draft in one undo step.
struct BookEditorSheet: View {
    @Environment(\.library) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.bookLookup) private var bookLookup
    @Environment(BookSources.self) private var sources
    var model: WindowModel
    /// Nil for Add Book.
    var editing: Book?
    var collections: [Collection]
    var onAdded: (UUID) -> Void
    var onShowBook: (UUID) -> Void
    /// Set when the scan sheet opened this Add Book.
    var scan: ScanEditorConfig?
    /// Puts the cursor in the ISBN field ("Type ISBN Instead").
    var focusISBN: Bool

    @State private var draft: BookDraft
    @State private var pendingAuthor = ""
    @State private var duplicates: DuplicateIndex
    @State private var usedLanguages: [String]
    @State private var lookup = LookupModel()
    @FocusState private var isbnFocused: Bool
    @State private var isbnLeft = false
    @State private var isScanning = false
    @State private var didAutoComplete = false
    /// The ISBN a scan put in the field: highlighted until the user changes it.
    @State private var scannedISBN: String?
    /// Mac: the selected tab. iOS: whether the synopsis page is pushed.
    @State private var tab: EditorTab
    /// The Details tab's height, which the Synopsis tab takes so the sheet keeps its size.
    @State private var detailsHeight: CGFloat = 0

    init(
        model: WindowModel, editing: Book?, books: [Book], collections: [Collection],
        onAdded: @escaping (UUID) -> Void, onShowBook: @escaping (UUID) -> Void,
        scan: ScanEditorConfig? = nil, focusISBN: Bool = false, initialTab: EditorTab = .details
    ) {
        _tab = State(initialValue: initialTab)
        self.model = model
        self.editing = editing
        self.collections = collections
        self.onAdded = onAdded
        self.onShowBook = onShowBook
        self.scan = scan
        self.focusISBN = focusISBN
        if let editing {
            _draft = State(initialValue: BookDraft(book: editing))
        } else {
            var fresh = BookDraft()
            fresh.language = LanguageOptions.defaultLanguage(books: books)
            if let scan, let prepared = scan.prepared {
                fresh = prepared.draft
                _scannedISBN = State(initialValue: fresh.isbnText)
                _didAutoComplete = State(initialValue: true)
                let model = LookupModel()
                model.adopt(prepared.result)
                _lookup = State(initialValue: model)
            } else if let scan {
                fresh.isbnText = scan.isbn.hyphenated
                // The first book of a round has Add Book's defaults; later ones
                // get the status and collections chosen for the one before.
                if scan.inARow { scan.round.apply(to: &fresh) }
                _scannedISBN = State(initialValue: fresh.isbnText)
            }
            _draft = State(initialValue: fresh)
        }
        _duplicates = State(initialValue: DuplicateIndex(books: books, excluding: editing?.id))
        _usedLanguages = State(initialValue: books.compactMap(\.language))
    }

    private var isEditing: Bool { editing != nil }
    private var duplicate: DuplicateIndex.Entry? { duplicates.match(for: draft) }

    // MARK: Lookup

    /// What Complete would search for, or nil while the sheet has too little.
    private var lookupQuery: LookupQuery? { LookupQuery(draft: draft, pendingAuthor: pendingAuthor) }

    private func isFilled(_ field: LookupField) -> Bool {
        lookup.result?.isHighlighted(field, in: draft) ?? false
    }

    /// The note under a field whose value differs from the found one.
    @ViewBuilder
    private func offerNote(_ field: LookupField) -> some View {
        if let result = lookup.result, result.showsOffer(field, in: draft) {
            let messages = LookupMessages(locale: locale)
            let value = result.offerValue(field, formatting: BookFormatting(locale: locale))
            LookupOfferNote(label: messages.offerLabel(source: result.source, value: value)) {
                lookup.use(field, draft: &draft)
            }
        }
    }

    private var coverOffer: (label: String, action: () -> Void)? {
        guard let result = lookup.result, result.showsOffer(.cover, in: draft) else { return nil }
        return (LookupMessages(locale: locale).coverOffer(source: result.source), { lookup.use(.cover, draft: &draft) })
    }

    /// The dot on the Synopsis tab or row: Complete filled the synopsis, or offers another.
    private var marksSynopsis: Bool {
        guard let result = lookup.result else { return false }
        return result.isHighlighted(.synopsis, in: draft) || result.showsOffer(.synopsis, in: draft)
    }

    private func complete() {
        guard let library else { return }
        commitPendingAuthor(library)
        guard let query = LookupQuery(draft: draft) else { return }
        lookup.start(query, draft: $draft, using: bookLookup, library: library)
    }

    /// The scan sheet over this editor read an ISBN: it replaces the field's
    /// value, and Add Book starts Complete. Edit Book only fills the field.
    private func fillISBN(_ isbn: ISBN) {
        draft.isbnText = isbn.hyphenated
        scannedISBN = draft.isbnText
        if !isEditing, sources.hasActiveSource { complete() }
    }

    private var isScannedISBN: Bool { scannedISBN != nil && draft.isbnText == scannedISBN }

    // MARK: ISBN

    private var isbnCheck: ISBN.Check { ISBN.parse(draft.isbnText) }

    /// Red from the moment 10 or 13 characters fail the checksum, or when the
    /// field is left with an incomplete value. Not after the first typed digit.
    private var showISBNError: Bool {
        switch isbnCheck {
        case .empty, .valid: false
        case .invalid: true
        case .incomplete: isbnLeft
        }
    }

    // MARK: Body

    var body: some View {
        #if os(iOS)
        NavigationStack {
            ScrollView { content }
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        } label: {
                            Label("Hide Keyboard", systemImage: "keyboard.chevron.compact.down")
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            lookup.stop()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isEditing ? "Save" : "Add") { save() }
                            .disabled(!draft.canSave || duplicate != nil)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: Binding(
                    get: { tab == .synopsis }, set: { tab = $0 ? .synopsis : .details }
                )) {
                    SynopsisEditor(draft: $draft, lookup: lookup)
                }
        }
        #else
        content
            .frame(width: 650)
            .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    private var content: some View {
        VStack(spacing: 0) {
            LookupHeader(
                title: isEditing ? "Edit Book" : "Add Book", lookup: lookup, canComplete: lookupQuery != nil,
                hasSources: sources.hasActiveSource,
                complete: complete, stop: { lookup.stop() }, undo: { lookup.undo(draft: &draft) }
            )
            #if os(macOS)
            EditorTabs(tab: $tab, marksSynopsis: marksSynopsis)
                .padding(.bottom, 12)
            if tab == .synopsis {
                SynopsisEditor(draft: $draft, lookup: lookup)
                    .frame(height: max(detailsHeight, 360))
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            } else {
                details
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailsHeight = $0 }
            }
            #else
            details
            #endif
            #if os(macOS)
            Divider()
            HStack {
                if let scan, scan.inARow, scan.round.count > 0 {
                    Text(verbatim: ScanMessages(locale: locale).addedInRound(scan.round.count))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    lookup.stop()
                    dismiss()
                }
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle) { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canSave || duplicate != nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            #endif
        }
        .onChange(of: draft.status) { _, status in
            if status == .reading, draft.startedAt == nil {
                draft.startedAt = Calendar.current.startOfDay(for: .now)
            }
        }
        .onChange(of: isbnFocused) { _, focused in
            guard !focused else { return }
            isbnLeft = true
            // A valid ISBN takes its one hyphenated form as soon as the field is left.
            let formatted = ISBN.formatted(draft.isbnText)
            if formatted != draft.isbnText { draft.isbnText = formatted }
        }
        // A hint goes away when what it is about changes.
        .onChange(of: draft.title) { lookup.clearHint() }
        .onChange(of: draft.authors) { lookup.clearHint() }
        .onChange(of: draft.isbnText) { lookup.clearHint() }
        .onDisappear { lookup.stop() }
        .onAppear {
            if focusISBN { isbnFocused = true }
            // A scanned ISBN is looked up at once.
            if scan != nil, !didAutoComplete {
                didAutoComplete = true
                if sources.hasActiveSource { complete() }
            }
        }
        .sheet(isPresented: Binding(
            get: { lookup.editions != nil },
            set: { if !$0 { lookup.cancelEditions() } }
        )) { editionPicker }
    }

    /// No ScrollView on the Mac: the sheet grows with the banner, hints and
    /// notes, so every field stays in view.
    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            form
            if let duplicate { duplicateBanner(duplicate) }
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    /// "Add and Scan Next" while a round goes on.
    private var primaryTitle: LocalizedStringKey {
        if isEditing { return "Save" }
        return scan?.inARow == true ? "Add and Scan Next" : "Add Book"
    }

    @ViewBuilder
    private var editionPicker: some View {
        if let list = lookup.editions, let query = lookup.query {
            EditionPickerSheet(
                list: list, query: query,
                use: { record in
                    guard let library else { return }
                    lookup.choose(record, draft: $draft, using: bookLookup, library: library)
                },
                cancel: { lookup.cancelEditions() }
            )
        }
    }

    // MARK: Fields

    /// One grid for the book fields and the status, so both share the label
    /// column, which grows to the widest label (German runs longer).
    private var form: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 10) {
            fields
            GridRow {
                Divider().gridCellColumns(2)
            }
            statusRows
        }
    }

    @ViewBuilder
    private var fields: some View {
        row("Title") {
            noted(.title) {
                TextField("Title", text: $draft.title).labelsHidden().lookupFilled(isFilled(.title))
            }
        }
        row("Subtitle") {
            noted(.subtitle) {
                TextField("Optional", text: $draft.subtitle).labelsHidden().lookupFilled(isFilled(.subtitle))
            }
        }
        row("Authors") {
            noted(.authors) {
                AuthorField(authors: $draft.authors, pendingName: $pendingAuthor)
                    // The highlight gets room around the chips without moving the layout.
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .lookupFilled(isFilled(.authors))
                    .padding(.horizontal, -4)
                    .padding(.vertical, -3)
            }
        }
        row("Year") {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                noted(.year) {
                    TextField("Year", text: $draft.yearText)
                        .labelsHidden()
                        .frame(width: 70)
                        .overlay(alignment: .trailing) { invalidMark(draft.issues.contains(.invalidYear)) }
                        .lookupFilled(isFilled(.year))
                }
                Text("Pages").foregroundStyle(.secondary)
                noted(.pages) {
                    TextField("Pages", text: $draft.pagesText)
                        .labelsHidden()
                        .frame(width: 70)
                        .overlay(alignment: .trailing) { invalidMark(draft.issues.contains(.invalidPages)) }
                        .lookupFilled(isFilled(.pages))
                }
                Spacer(minLength: 0)
            }
        }
        #if os(iOS)
        // Two rows: the Mac's one row is wider than a phone.
        row("Language") {
            noted(.language) {
                languagePicker("Language", selection: $draft.language).lookupFilled(isFilled(.language))
            }
        }
        row("Original Language") {
            noted(.originalLanguage) {
                languagePicker("Original Language", selection: $draft.originalLanguage)
                    .lookupFilled(isFilled(.originalLanguage))
            }
        }
        #else
        row("Language") {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                noted(.language) {
                    languagePicker("Language", selection: $draft.language).lookupFilled(isFilled(.language))
                }
                Text("Original Language").foregroundStyle(.secondary)
                noted(.originalLanguage) {
                    languagePicker("Original Language", selection: $draft.originalLanguage)
                        .lookupFilled(isFilled(.originalLanguage))
                }
                Spacer(minLength: 0)
            }
        }
        #endif
        row("Publisher") {
            noted(.publisher) {
                TextField("Optional", text: $draft.publisher).labelsHidden().lookupFilled(isFilled(.publisher))
            }
        }
        row("ISBN") {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    TextField("ISBN", text: $draft.isbnText)
                        .labelsHidden()
                        .focused($isbnFocused)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Theme.error, lineWidth: showISBNError ? 1.5 : 0)
                        }
                        .lookupFilled(isFilled(.isbn) || isScannedISBN)
                        .accessibilityLabel("ISBN")
                    // Not in the scan flow: the scan sheet under this one owns the camera.
                    if scan == nil { scanButton }
                }
                if showISBNError {
                    Text("This ISBN is not valid. Check the last digit.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.error)
                }
                offerNote(.isbn)
            }
        }
        #if os(iOS)
        row("Synopsis") { synopsisRow }
        #endif
        row("Cover") {
            CoverPicker(
                coverData: $draft.coverData, title: draft.title,
                author: draft.authors.map(\.name).joined(separator: ", "),
                highlighted: isFilled(.cover), offer: coverOffer
            )
        }
    }

    #if os(iOS)
    /// The first two lines of the synopsis, or "None"; opens the synopsis page.
    private var synopsisRow: some View {
        Button {
            tab = .synopsis
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if draft.synopsis.isEmpty {
                    // "Keiner" in German: the synopsis is masculine, the languages' "None" is not.
                    Text("synopsis.none").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: draft.synopsis)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if marksSynopsis {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                        .accessibilityLabel("Filled by Complete")
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Synopsis")
    }
    #endif

    private var scanButton: some View {
        Button {
            isScanning = true
        } label: {
            Image(systemName: "barcode.viewfinder")
        }
        .help("Scan Barcode")
        .accessibilityLabel("Scan Barcode")
        #if os(iOS)
        .fullScreenCover(isPresented: $isScanning) {
            ScanScreen(mode: .fillISBN { isbn in fillISBN(isbn) }, model: model, books: [], collections: [])
        }
        #else
        .sheet(isPresented: $isScanning) {
            ScanSheet(mode: .fillISBN { isbn in fillISBN(isbn) }, model: model, books: [], collections: [])
        }
        #endif
    }

    /// A field with the lookup's offer note under it.
    private func noted<Content: View>(_ field: LookupField, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            content()
            offerNote(field)
        }
    }

    private func row<Content: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .fixedSize()
                .frame(minWidth: 70, alignment: .trailing)
                .gridColumnAlignment(.trailing)
            content()
        }
    }

    @ViewBuilder
    private func invalidMark(_ invalid: Bool) -> some View {
        if invalid {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Theme.error)
                .padding(.trailing, 4)
                .accessibilityLabel("Invalid value")
        }
    }

    private func languagePicker(_ label: LocalizedStringKey, selection: Binding<String?>) -> some View {
        let options = LanguageOptions.codes(used: usedLanguages, locale: locale)
        return Picker(label, selection: selection) {
            Text("None").tag(String?.none)
            if !options.used.isEmpty {
                Divider()
                ForEach(options.used, id: \.self) { code in
                    Text(LanguageOptions.name(code, locale)).tag(String?.some(code))
                }
            }
            Divider()
            ForEach(options.others, id: \.self) { code in
                Text(LanguageOptions.name(code, locale)).tag(String?.some(code))
            }
        }
        .labelsHidden()
        #if os(iOS)
        // Left-aligned like the text fields; an iOS menu centres its label in a fixed width.
        .fixedSize()
        #else
        .frame(width: 150)
        #endif
    }

    // MARK: Status

    @ViewBuilder
    private var statusRows: some View {
        row("Status") {
            StatusSegments(status: $draft.status)
        }
        switch draft.status {
        case .reading:
            row("Started") {
                DateField(label: "Started", date: startedBinding)
            }
        case .read:
            row("Started") { OptionalDatePicker(date: $draft.startedAt, label: "Started") }
            row("Finished on") { OptionalDatePicker(date: $draft.finishedAt, label: "Finished on") }
            if draft.issues.contains(.finishBeforeStart) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("The finish date can't be before the start date.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.error)
                }
            }
            row("Rating") { StarRatingControl(rating: $draft.rating) }
            row("Notes") {
                TextEditor(text: $draft.notes)
                    .font(.body)
                    .frame(height: 70)
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)) }
                    .accessibilityLabel("Notes")
            }
        case .wantToRead, nil:
            EmptyView()
        }
        row("Collections") { collectionChips }
        row("Date Added") {
            DateField(label: "Date Added", date: $draft.addedAt, through: Date.now)
        }
    }

    private var startedBinding: Binding<Date> {
        Binding(
            get: { draft.startedAt ?? Calendar.current.startOfDay(for: .now) },
            set: { draft.startedAt = $0 }
        )
    }

    private var collectionChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(collections.filter { draft.collectionIDs.contains($0.id) }) { collection in
                Chip {
                    HStack(spacing: 4) {
                        Text(collection.name)
                        Button {
                            draft.collectionIDs.removeAll { $0 == collection.id }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(collection.name)")
                    }
                }
            }
            let remaining = collections.filter { !draft.collectionIDs.contains($0.id) }
            if !remaining.isEmpty {
                Menu {
                    ForEach(remaining) { collection in
                        Button(collection.name) { draft.collectionIDs.append(collection.id) }
                    }
                } label: {
                    Chip(dashed: true) { Text("+ Add") }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    // MARK: Duplicate

    private func duplicateBanner(_ entry: DuplicateIndex.Entry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Already in your library: \(entry.label)")
                .font(.system(size: 13))
            Spacer()
            Button("Show Book") {
                dismiss()
                onShowBook(entry.bookID)
            }
            Button("Add Anyway") { save(ignoringDuplicate: true) }
                .disabled(!draft.canSave)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    // MARK: Save

    private func save(ignoringDuplicate: Bool = false) {
        guard let library else { return }
        // A running lookup ends here; the book is saved with what the user entered.
        lookup.stop()
        commitPendingAuthor(library)
        guard draft.canSave, ignoringDuplicate || duplicate == nil else { return }
        model.attempt {
            if let editing {
                try library.updateBook(editing, with: draft)
            } else {
                // Origin and lookup id only when something from the lookup is still in the draft.
                if let result = lookup.result, result.hasHighlight(in: draft) {
                    let book = try library.addBook(draft, origin: .lookup, originNote: result.recordID)
                    onAdded(book.id)
                    scan?.onSaved(draft, book.id)
                } else {
                    let book = try library.addBook(draft)
                    onAdded(book.id)
                    scan?.onSaved(draft, book.id)
                }
            }
            dismiss()
        }
    }

    private func commitPendingAuthor(_ library: Library) {
        let name = AuthorName.normalize(pendingAuthor)
        pendingAuthor = ""
        guard !name.isEmpty else { return }
        let author = library.suggestedAuthor(for: name)
        if !draft.authors.contains(where: { AuthorName.matchKey($0.name) == AuthorName.matchKey(author.name) }) {
            draft.authors.append(author)
        }
    }
}

/// A date that may be missing: the day as a button that opens a calendar,
/// or "Optional" in grey when there is none. The calendar has Today (when no
/// day is set, since picking the already selected day changes nothing) and
/// Remove Date (when one is).
struct OptionalDatePicker: View {
    @Environment(\.locale) private var locale
    @Environment(\.isEnabled) private var isEnabled
    @Binding var date: Date?
    /// Used as the accessibility label.
    var label: LocalizedStringKey = "Date"

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            HStack(spacing: 6) {
                if let date {
                    Text(BookFormatting(locale: locale).day(date)).monospacedDigit()
                } else {
                    Text("Optional").foregroundStyle(.secondary)
                }
                Image(systemName: "calendar").foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(Text(label))
        .accessibilityValue(date.map { BookFormatting(locale: locale).day($0) } ?? String(localized: "Optional"))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                DatePicker(label, selection: Binding(
                    get: { date ?? Calendar.current.startOfDay(for: .now) },
                    set: { picked in
                        date = Calendar.current.startOfDay(for: picked)
                        isOpen = false
                    }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                HStack {
                    if date == nil {
                        Button("Today") {
                            date = Calendar.current.startOfDay(for: .now)
                            isOpen = false
                        }
                    } else {
                        Button("Remove Date", role: .destructive) {
                            date = nil
                            isOpen = false
                        }
                    }
                }
            }
            .padding(12)
        }
        .onChange(of: isEnabled) { _, enabled in if !enabled { isOpen = false } }
    }
}
