import SwiftUI
import BuchhalterCore

/// Add Book and Edit Book: one sheet, one `BookDraft`, validated while the
/// user types. The store applies the draft in one undo step.
struct BookEditorSheet: View {
    @Environment(\.library) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    var model: WindowModel
    /// Nil for Add Book.
    var editing: Book?
    var collections: [Collection]
    var onAdded: (UUID) -> Void
    var onShowBook: (UUID) -> Void

    @State private var draft: BookDraft
    @State private var pendingAuthor = ""
    @State private var duplicates: DuplicateIndex
    @State private var usedLanguages: [String]
    @FocusState private var isbnFocused: Bool
    @State private var isbnLeft = false

    init(
        model: WindowModel, editing: Book?, books: [Book], collections: [Collection],
        onAdded: @escaping (UUID) -> Void, onShowBook: @escaping (UUID) -> Void
    ) {
        self.model = model
        self.editing = editing
        self.collections = collections
        self.onAdded = onAdded
        self.onShowBook = onShowBook
        if let editing {
            _draft = State(initialValue: BookDraft(book: editing))
        } else {
            var fresh = BookDraft()
            fresh.language = LanguageOptions.defaultLanguage(books: books)
            _draft = State(initialValue: fresh)
        }
        _duplicates = State(initialValue: DuplicateIndex(books: books, excluding: editing?.id))
        _usedLanguages = State(initialValue: books.compactMap(\.language))
    }

    private var isEditing: Bool { editing != nil }
    private var duplicate: DuplicateIndex.Entry? { duplicates.match(for: draft) }

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
        VStack(spacing: 0) {
            Text(isEditing ? "Edit Book" : "Add Book")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    form
                    if let duplicate { duplicateBanner(duplicate) }
                }
                .padding(.horizontal, 24)
                // The ScrollView clips to its bounds; the top inset keeps the
                // first field's focus ring visible.
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add Book") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canSave || duplicate != nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 620)
        .frame(minHeight: 420, idealHeight: 640, maxHeight: 760)
        .onChange(of: draft.status) { _, status in
            if status == .reading, draft.startedAt == nil {
                draft.startedAt = Calendar.current.startOfDay(for: .now)
            }
        }
        .onChange(of: isbnFocused) { _, focused in if !focused { isbnLeft = true } }
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
            TextField("Title", text: $draft.title).labelsHidden()
        }
        row("Subtitle") {
            TextField("Optional", text: $draft.subtitle).labelsHidden()
        }
        row("Authors") {
            AuthorField(authors: $draft.authors, pendingName: $pendingAuthor)
        }
        row("Year") {
            HStack(spacing: 12) {
                TextField("Year", text: $draft.yearText)
                    .labelsHidden()
                    .frame(width: 70)
                    .overlay(alignment: .trailing) { invalidMark(draft.issues.contains(.invalidYear)) }
                Text("Pages").foregroundStyle(.secondary)
                TextField("Pages", text: $draft.pagesText)
                    .labelsHidden()
                    .frame(width: 70)
                    .overlay(alignment: .trailing) { invalidMark(draft.issues.contains(.invalidPages)) }
                Spacer(minLength: 0)
            }
        }
        row("Language") {
            HStack(spacing: 12) {
                languagePicker("Language", selection: $draft.language)
                Text("Original Language").foregroundStyle(.secondary)
                languagePicker("Original Language", selection: $draft.originalLanguage)
                Spacer(minLength: 0)
            }
        }
        row("Publisher") {
            TextField("Optional", text: $draft.publisher).labelsHidden()
        }
        row("ISBN") {
            VStack(alignment: .leading, spacing: 3) {
                TextField("ISBN", text: $draft.isbnText)
                    .labelsHidden()
                    .focused($isbnFocused)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Theme.error, lineWidth: showISBNError ? 1.5 : 0)
                    }
                    .accessibilityLabel("ISBN")
                if showISBNError {
                    Text("This ISBN is not valid. Check the last digit.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.error)
                }
            }
        }
        row("Cover") {
            CoverPicker(
                coverData: $draft.coverData, title: draft.title,
                author: draft.authors.map(\.name).joined(separator: ", ")
            )
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
        .frame(width: 150)
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
                DatePicker("Started", selection: startedBinding, displayedComponents: .date).labelsHidden()
            }
        case .read:
            row("Started") { OptionalDatePicker(date: $draft.startedAt) }
            row("Finished on") {
                DatePicker("Finished", selection: $draft.finishedAt, displayedComponents: .date).labelsHidden()
            }
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
        commitPendingAuthor(library)
        guard draft.canSave, ignoringDuplicate || duplicate == nil else { return }
        model.attempt {
            if let editing {
                try library.updateBook(editing, with: draft)
            } else {
                let book = try library.addBook(draft)
                onAdded(book.id)
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

/// A toggle and a date, for a date that may be missing.
struct OptionalDatePicker: View {
    @Binding var date: Date?

    var body: some View {
        HStack {
            Toggle("Set date", isOn: Binding(
                get: { date != nil },
                set: { date = $0 ? Calendar.current.startOfDay(for: .now) : nil }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            if date != nil {
                DatePicker("Date", selection: Binding(
                    get: { date ?? .now }, set: { date = $0 }
                ), displayedComponents: .date)
                .labelsHidden()
            } else {
                Text("Optional").foregroundStyle(.secondary)
            }
        }
    }
}
