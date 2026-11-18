import Foundation

/// The fields Complete can fill or offer. Status, dates, rating, notes and
/// collections are not in this list on purpose: a lookup never touches them.
/// The synopsis carries its source along: filling or using it copies both.
public enum LookupField: CaseIterable, Hashable, Sendable {
    case title, subtitle, authors, year, pages, language, originalLanguage, publisher, isbn, cover, synopsis
}

/// What a lookup did to a draft, kept so the sheet can show it and undo it.
///
/// The result stores the draft as it was before (`original`) and the record's
/// values as a full draft (`proposed`). What the sheet shows is derived from
/// those two and the current draft, so nothing drifts: a field is highlighted
/// while it still holds the found value, a note shows while a differing value
/// is on offer, and the user's edits change both without any bookkeeping.
public struct LookupResult: Equatable, Sendable {
    public let source: LookupSource
    /// Stored as the new book's origin note, so the data can be refreshed later.
    public let recordID: String
    /// The draft before Complete.
    public let original: BookDraft
    /// The draft with every value the record has.
    public let proposed: BookDraft
    /// Fields that were empty and are now filled.
    public let filled: Set<LookupField>
    /// Fields that differ and keep the user's value until `use`.
    public let offered: Set<LookupField>
    /// Offered fields the user took.
    public private(set) var used: Set<LookupField> = []

    /// The cover counts as a field, so the spec's German example (4 filled, 2 differing) holds.
    public var filledCount: Int { filled.count }
    public var differCount: Int { offered.count }

    // MARK: Merge

    /// Applies a record to a draft: an empty field is filled, an equal one is
    /// left alone, a different one keeps the user's value and is offered. A
    /// title that is not empty is only ever offered. Values typed while the
    /// lookup ran are in `draft` and win.
    public static func merge(
        _ record: LookupRecord, authors: [AuthorDraft], cover: Data?, synopsis: Synopsis? = nil,
        into draft: BookDraft, locale: Locale = .current
    ) -> (draft: BookDraft, result: LookupResult) {
        var proposed = draft
        proposed.title = record.title
        if let subtitle = record.subtitle { proposed.subtitle = subtitle }
        if !authors.isEmpty { proposed.authors = authors }
        if let year = record.year { proposed.yearText = String(year) }
        if let pages = record.pages { proposed.pagesText = String(pages) }
        if let code = record.language, LanguageOptions.isOffered(code, locale: locale) { proposed.language = code }
        if let code = record.originalLanguage, LanguageOptions.isOffered(code, locale: locale) {
            proposed.originalLanguage = code
        }
        if let publisher = record.publisher { proposed.publisher = publisher }
        if let isbn = record.isbnDisplay ?? record.isbn13s.first { proposed.isbnText = ISBN.formatted(isbn) }
        if let cover { proposed.coverData = cover }
        if let synopsis {
            proposed.synopsis = synopsis.text
            proposed.synopsisSource = synopsis.source
        }

        var merged = draft
        var filled = Set<LookupField>()
        var offered = Set<LookupField>()
        for field in LookupField.allCases where !same(field, draft, proposed) {
            if isEmpty(field, draft) {
                copy(field, from: proposed, to: &merged)
                filled.insert(field)
            } else {
                offered.insert(field)
            }
        }
        let result = LookupResult(
            source: record.source, recordID: record.id, original: draft, proposed: proposed,
            filled: filled, offered: offered
        )
        return (merged, result)
    }

    // MARK: What the sheet shows

    /// Green while the field holds the value Complete or `use` put there.
    /// Editing it removes the highlight.
    public func isHighlighted(_ field: LookupField, in draft: BookDraft) -> Bool {
        (filled.contains(field) || used.contains(field)) && Self.identical(field, draft, proposed)
    }

    /// The note "DNB: 2009 · Use" shows while a differing value is on offer.
    public func showsOffer(_ field: LookupField, in draft: BookDraft) -> Bool {
        offered.contains(field) && !used.contains(field) && !Self.same(field, draft, proposed)
    }

    /// True when at least one field still shows a highlight.
    public func hasHighlight(in draft: BookDraft) -> Bool {
        LookupField.allCases.contains { isHighlighted($0, in: draft) }
    }

    /// Takes the found value for one field.
    public mutating func use(_ field: LookupField, on draft: BookDraft) -> BookDraft {
        var result = draft
        Self.copy(field, from: proposed, to: &result)
        used.insert(field)
        return result
    }

    /// Puts every filled field and every used field back to its value before Complete.
    public func undo(on draft: BookDraft) -> BookDraft {
        var result = draft
        for field in filled.union(used) { Self.copy(field, from: original, to: &result) }
        return result
    }

    /// The found value as text, for the note: "2009", "173", "Deutsch", a name list, an ISBN.
    public func offerValue(_ field: LookupField, formatting: BookFormatting) -> String {
        switch field {
        case .title: proposed.title
        case .subtitle: proposed.subtitle
        case .authors: proposed.authors.map(\.name).formatted(.list(type: .and).locale(formatting.locale))
        case .year: proposed.yearText
        case .pages: proposed.pagesText
        case .language: proposed.language.map(formatting.languageName) ?? ""
        case .originalLanguage: proposed.originalLanguage.map(formatting.languageName) ?? ""
        case .publisher: proposed.publisher
        case .isbn: proposed.isbnText
        case .cover: ""
        case .synopsis: proposed.synopsis
        }
    }

    /// The source of the offered synopsis, for "Google Books has a different synopsis".
    public var offeredSynopsisSource: LookupSource? { proposed.synopsisSource }

    // MARK: Field access

    private static func isEmpty(_ field: LookupField, _ draft: BookDraft) -> Bool {
        func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch field {
        case .title: return blank(draft.title)
        case .subtitle: return blank(draft.subtitle)
        case .authors: return draft.authors.isEmpty
        case .year: return blank(draft.yearText)
        case .pages: return blank(draft.pagesText)
        case .language: return draft.language == nil
        case .originalLanguage: return draft.originalLanguage == nil
        case .publisher: return blank(draft.publisher)
        case .isbn: return blank(draft.isbnText)
        case .cover: return draft.coverData == nil
        case .synopsis: return blank(draft.synopsis)
        }
    }

    /// "Same value" without case and diacritics: "Ryu Murakami" is "Ryū
    /// Murakami", "liebeskind" is "Liebeskind", years compare as numbers and
    /// ISBNs as ISBN-13.
    private static func same(_ field: LookupField, _ a: BookDraft, _ b: BookDraft) -> Bool {
        func text(_ x: String, _ y: String) -> Bool {
            TextFolding.fold(AuthorName.normalize(x)) == TextFolding.fold(AuthorName.normalize(y))
        }
        switch field {
        case .title: return text(a.title, b.title)
        case .subtitle: return text(a.subtitle, b.subtitle)
        case .authors: return Set(a.authors.map { AuthorName.matchKey($0.name) }) == Set(b.authors.map { AuthorName.matchKey($0.name) })
        case .year: return a.year == b.year && (a.year != nil || text(a.yearText, b.yearText))
        case .pages: return a.pages == b.pages && (a.pages != nil || text(a.pagesText, b.pagesText))
        case .language: return a.language == b.language
        case .originalLanguage: return a.originalLanguage == b.originalLanguage
        case .publisher: return text(a.publisher, b.publisher)
        case .isbn:
            if case .valid(let x) = ISBN.parse(a.isbnText), case .valid(let y) = ISBN.parse(b.isbnText) { return x == y }
            return text(a.isbnText, b.isbnText)
        case .cover: return a.coverData == b.coverData
        case .synopsis: return synopsisKey(a.synopsis) == synopsisKey(b.synopsis)
        }
    }

    /// Folded, with every run of whitespace as one space: a text that differs
    /// only in line breaks or case is the same text.
    private static func synopsisKey(_ text: String) -> String {
        TextFolding.fold(text.split(whereSeparator: \.isWhitespace).joined(separator: " "))
    }

    /// Exact equality, for the highlight: the user changing a letter ends it.
    private static func identical(_ field: LookupField, _ a: BookDraft, _ b: BookDraft) -> Bool {
        func text(_ x: String, _ y: String) -> Bool {
            x.trimmingCharacters(in: .whitespacesAndNewlines) == y.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch field {
        case .title: return text(a.title, b.title)
        case .subtitle: return text(a.subtitle, b.subtitle)
        case .authors: return a.authors.map(\.name) == b.authors.map(\.name)
        case .year: return text(a.yearText, b.yearText)
        case .pages: return text(a.pagesText, b.pagesText)
        case .language: return a.language == b.language
        case .originalLanguage: return a.originalLanguage == b.originalLanguage
        case .publisher: return text(a.publisher, b.publisher)
        case .isbn: return text(a.isbnText, b.isbnText)
        case .cover: return a.coverData == b.coverData
        case .synopsis: return text(a.synopsis, b.synopsis)
        }
    }

    private static func copy(_ field: LookupField, from source: BookDraft, to target: inout BookDraft) {
        switch field {
        case .title: target.title = source.title
        case .subtitle: target.subtitle = source.subtitle
        case .authors: target.authors = source.authors
        case .year: target.yearText = source.yearText
        case .pages: target.pagesText = source.pagesText
        case .language: target.language = source.language
        case .originalLanguage: target.originalLanguage = source.originalLanguage
        case .publisher: target.publisher = source.publisher
        case .isbn: target.isbnText = source.isbnText
        case .cover: target.coverData = source.coverData
        case .synopsis:
            target.synopsis = source.synopsis
            target.synopsisSource = source.synopsisSource
        }
    }
}
