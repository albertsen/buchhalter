import Foundation
import SwiftData

@MainActor
extension Library {
    // MARK: Add, update, delete

    /// Adds a book with its authors, one reading, and collection memberships
    /// in one undo step.
    @discardableResult
    public func addBook(
        _ draft: BookDraft, origin: BookOrigin = .manual, originNote: String? = nil
    ) throws -> Book {
        try validate(draft)
        return try change("Add Book") {
            let book = Book()
            book.originRaw = origin.rawValue
            book.originNote = trimmedOrNil(originNote)
            context.insert(book)
            apply(draft, to: book)
            setAuthors(draft.authors, on: book)
            try applyDraftStatus(draft, to: book)
            setCollections(draft.collectionIDs, on: book)
            return book
        }
    }

    public func updateBook(_ book: Book, with draft: BookDraft) throws {
        try validate(draft)
        try change("Edit Book", covers: [book]) {
            apply(draft, to: book)
            setAuthors(draft.authors, on: book)
            try applyDraftStatus(draft, to: book)
            setCollections(draft.collectionIDs, on: book)
        }
    }

    /// Inline editing in the detail: changes the book's own fields (title,
    /// subtitle, authors, year, pages, languages, publisher, ISBN, added date)
    /// in one undo step. Unlike `updateBook` it never touches the readings,
    /// the collections or the cover: a draft cannot hold a finished reading
    /// without a date, so going through the status would date it today.
    public func updateDetails(of book: Book, _ edit: (inout BookDraft) -> Void) throws {
        var draft = BookDraft(book: book)
        edit(&draft)
        try validate(draft)
        let issues = draft.issues
        if issues.contains(.invalidYear) { throw LibraryError.invalidYear }
        if issues.contains(.invalidPages) { throw LibraryError.invalidPages }
        try change("Edit Book") {
            apply(draft, to: book, includingCover: false)
            setAuthors(draft.authors, on: book)
        }
    }

    /// Deletes the book with its readings and authorships. Authors stay, which
    /// keeps their corrected sort names. Collections keep their other books.
    public func deleteBook(_ book: Book) throws {
        try change("Delete Book", covers: [book]) {
            context.delete(book)
        }
    }

    /// Find Synopsis and Remove Synopsis: sets or clears the synopsis alone,
    /// in one undo step. A source is kept only with a text.
    public func setSynopsis(_ text: String?, source: LookupSource?, for book: Book) throws {
        let trimmed = trimmedOrNil(text ?? "")
        try change(trimmed == nil ? "Remove Synopsis" : "Find Synopsis") {
            book.synopsis = trimmed
            book.synopsisSourceRaw = trimmed == nil ? nil : source?.rawValue
        }
    }

    public func setCover(_ data: Data?, for book: Book) throws {
        try change("Change Cover", covers: [book]) {
            book.coverImage = data
        }
    }

    /// Changes the sort name of an author, and with it the order of all that
    /// author's books and the author's place in Authors.
    public func setSortName(_ sortName: String, for author: Author) throws {
        try change("Edit Sorted As") {
            let trimmed = AuthorName.normalize(sortName)
            author.sortName = trimmed.isEmpty ? AuthorName.guessSortName(author.name) : trimmed
        }
    }

    // MARK: Authors

    /// The stored sort name for a typed name, or the guess when the author is new.
    public func suggestedAuthor(for name: String) -> AuthorDraft {
        let normalized = AuthorName.normalize(name)
        if let existing = existingAuthors()[AuthorName.matchKey(normalized)] {
            return AuthorDraft(name: existing.name, sortName: existing.sortName, isExisting: true)
        }
        return AuthorDraft(name: normalized, sortName: AuthorName.guessSortName(normalized))
    }

    /// Authors keyed by folded name, newest duplicate loses to the first found.
    func existingAuthors() -> [String: Author] {
        let all = (try? context.fetch(FetchDescriptor<Author>())) ?? []
        var result: [String: Author] = [:]
        for author in all.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            result[AuthorName.matchKey(author.name)] = result[AuthorName.matchKey(author.name)] ?? author
        }
        return result
    }

    /// Reuses existing authors (case- and diacritic-folded name), creates new
    /// ones, and applies sort names the user edited. Order is the draft's order.
    @discardableResult
    public func resolveAuthors(_ drafts: [AuthorDraft]) -> [Author] {
        var known = existingAuthors()
        var result: [Author] = []
        for draft in drafts {
            let name = AuthorName.normalize(draft.name)
            guard !name.isEmpty else { continue }
            let key = AuthorName.matchKey(name)
            let sortName = AuthorName.normalize(draft.sortName)
            let author: Author
            if let existing = known[key] {
                author = existing
                if !sortName.isEmpty, existing.sortName != sortName { existing.sortName = sortName }
            } else {
                author = Author()
                author.name = name
                author.sortName = sortName.isEmpty ? AuthorName.guessSortName(name) : sortName
                context.insert(author)
                known[key] = author
            }
            if !result.contains(where: { $0 === author }) { result.append(author) }
        }
        return result
    }

    // MARK: Helpers

    func validate(_ draft: BookDraft) throws {
        let issues = draft.issues
        if issues.contains(.emptyTitle) { throw LibraryError.emptyTitle }
        if issues.contains(.invalidISBN) { throw LibraryError.invalidISBN }
        if issues.contains(.finishBeforeStart) { throw LibraryError.finishBeforeStart }
    }

    private func apply(_ draft: BookDraft, to book: Book, includingCover: Bool = true) {
        book.title = AuthorName.normalize(draft.title)
        book.subtitle = trimmedOrNil(draft.subtitle)
        book.publisher = trimmedOrNil(draft.publisher)
        book.year = draft.year
        book.pageCount = draft.pages
        book.language = draft.language
        book.originalLanguage = draft.originalLanguage == draft.language ? nil : draft.originalLanguage
        if includingCover { book.coverImage = draft.coverData }
        book.synopsis = trimmedOrNil(draft.synopsis)
        book.synopsisSourceRaw = book.synopsis == nil ? nil : draft.synopsisSource?.rawValue
        book.addedAt = draft.addedAt
        let isbn = trimmedOrNil(draft.isbnText)
        // A valid ISBN is always stored in its one hyphenated form.
        book.isbnText = isbn.map(ISBN.formatted)
        if let isbn, case .valid(let value) = ISBN.parse(isbn) {
            book.isbn13 = value.isbn13
        } else {
            book.isbn13 = nil
        }
    }

    /// Rebuilds the authorships in the draft's order, keeping those whose
    /// author stays and removing the rest.
    private func setAuthors(_ drafts: [AuthorDraft], on book: Book) {
        let authors = resolveAuthors(drafts)
        var existing = book.authorships ?? []
        for (position, author) in authors.enumerated() {
            if let index = existing.firstIndex(where: { $0.author === author }) {
                let authorship = existing.remove(at: index)
                if authorship.position != position { authorship.position = position }
            } else {
                let authorship = Authorship()
                authorship.position = position
                context.insert(authorship)
                authorship.book = book
                authorship.author = author
            }
        }
        for leftover in existing { context.delete(leftover) }
    }

    private func setCollections(_ ids: [UUID], on book: Book) {
        let wanted = Set(ids)
        let current = book.collections ?? []
        for collection in current where !wanted.contains(collection.id) {
            book.collections?.removeAll { $0 === collection }
        }
        let have = Set(current.map(\.id))
        for collection in fetchCollections() where wanted.contains(collection.id) && !have.contains(collection.id) {
            book.collections?.append(collection)
        }
    }
}
