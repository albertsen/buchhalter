import Foundation
import Testing
@testable import BuchhalterCore

struct LookupMergeTests {
    private let locale = Locale(identifier: "en")
    private let cover = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])

    private func piercing() throws -> LookupRecord {
        let marc = try #require(try MARCXMLParser.parse(fixture("dnb-isbn-piercing.xml")).records.first)
        return try #require(DNBRecordMapper.record(from: marc))
    }

    private let recordAuthors = [AuthorDraft(name: "Ryū Murakami", sortName: "Murakami, Ryū")]

    /// The spec's Edit Book example: year 1994, pages 176, typed author, own title.
    private func editDraft() -> BookDraft {
        var draft = BookDraft()
        draft.title = "Piercing"
        draft.authors = [AuthorDraft(name: "Ryu Murakami", sortName: "Murakami, Ryu", isExisting: true)]
        draft.yearText = "1994"
        draft.pagesText = "176"
        draft.language = "de"
        draft.isbnText = "978-3935890595"
        return draft
    }

    @Test func emptyDraftIsFilledWithEveryField() throws {
        let record = try piercing()
        let (merged, result) = LookupResult.merge(record, authors: recordAuthors, cover: nil, into: BookDraft(), locale: locale)
        #expect(result.filled == [.title, .subtitle, .authors, .year, .pages, .language, .originalLanguage, .publisher, .isbn])
        #expect(result.filledCount == 9 && result.differCount == 0)
        #expect(merged.title == "Piercing" && merged.subtitle == "Roman")
        #expect(merged.authors.map(\.name) == ["Ryū Murakami"])
        #expect(merged.yearText == "2009" && merged.pagesText == "173")
        #expect(merged.language == "de" && merged.originalLanguage == "ja")
        #expect(merged.publisher == "Liebeskind")
        #expect(merged.isbnText == "978-3-935890-59-5")
        #expect(merged.coverData == nil)

        let (withCover, coverResult) = LookupResult.merge(record, authors: recordAuthors, cover: cover, into: BookDraft(), locale: locale)
        #expect(coverResult.filled.contains(.cover) && coverResult.filledCount == 10)
        #expect(withCover.coverData == cover)
    }

    @Test func specExampleFillsFourAndOffersTwo() throws {
        let (merged, result) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: cover, into: editDraft(), locale: locale)
        #expect(result.filled == [.subtitle, .publisher, .originalLanguage, .cover])
        #expect(result.offered == [.year, .pages])
        #expect(result.filledCount == 4 && result.differCount == 2)
        // The user's values stay.
        #expect(merged.yearText == "1994" && merged.pagesText == "176")
        #expect(merged.title == "Piercing")
        #expect(merged.authors.map(\.name) == ["Ryu Murakami"])
        #expect(merged.subtitle == "Roman" && merged.publisher == "Liebeskind" && merged.originalLanguage == "ja")
        #expect(merged.coverData == cover)

        let formatting = BookFormatting(locale: locale)
        #expect(result.offerValue(.year, formatting: formatting) == "2009")
        #expect(result.offerValue(.pages, formatting: formatting) == "173")
        #expect(result.showsOffer(.year, in: merged) && result.showsOffer(.pages, in: merged))
        #expect(!result.showsOffer(.subtitle, in: merged))
    }

    @Test func theTitleIsNeverReplaced() throws {
        var draft = editDraft()
        draft.title = "Piercing (Neuausgabe)"
        let (merged, result) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: nil, into: draft, locale: locale)
        #expect(merged.title == "Piercing (Neuausgabe)")
        #expect(result.offered.contains(.title))
        #expect(result.offerValue(.title, formatting: BookFormatting(locale: locale)) == "Piercing")
    }

    @Test func caseAndDiacriticDifferencesAreTheSameValue() throws {
        var draft = editDraft()
        draft.publisher = "liebeskind"
        draft.subtitle = "ROMAN"
        let (_, result) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: nil, into: draft, locale: locale)
        #expect(!result.offered.contains(.publisher) && !result.offered.contains(.subtitle))
        #expect(!result.filled.contains(.publisher))
        #expect(!result.offered.contains(.authors))
        #expect(!result.offered.contains(.isbn))
    }

    @Test func aDifferentISBNAndAuthorsAreOffered() throws {
        var draft = editDraft()
        draft.isbnText = "978-3-15-011537-4"
        draft.authors.append(AuthorDraft(name: "Someone Else", sortName: "Else, Someone"))
        let (merged, result) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: nil, into: draft, locale: locale)
        #expect(result.offered.isSuperset(of: [.isbn, .authors]))
        #expect(merged.isbnText == "978-3-15-011537-4")
        #expect(merged.authors.count == 2)
    }

    @Test func aLanguageThePopupsDoNotOfferIsIgnored() throws {
        var record = try piercing()
        record.language = "zz"
        record.originalLanguage = "qq"
        var draft = BookDraft()
        draft.language = "en"
        let (merged, result) = LookupResult.merge(record, authors: recordAuthors, cover: nil, into: draft, locale: locale)
        #expect(merged.language == "en" && merged.originalLanguage == nil)
        #expect(!result.filled.contains(.language) && !result.offered.contains(.language))
        #expect(!result.filled.contains(.originalLanguage))
    }

    @Test func aRecordWithoutAnOriginalLanguageLeavesTheFieldAlone() throws {
        var record = try piercing()
        record.originalLanguage = nil
        var draft = editDraft()
        draft.originalLanguage = "fr"
        let (merged, result) = LookupResult.merge(record, authors: recordAuthors, cover: nil, into: draft, locale: locale)
        #expect(merged.originalLanguage == "fr")
        #expect(!result.offered.contains(.originalLanguage) && !result.filled.contains(.originalLanguage))
    }

    @Test func aDraftWithACoverOffersTheNewOne() throws {
        var draft = editDraft()
        draft.coverData = Data([0xFF, 0xD8, 0xFF, 9, 9, 9])
        let (merged, result) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: cover, into: draft, locale: locale)
        #expect(result.offered.contains(.cover) && !result.filled.contains(.cover))
        #expect(merged.coverData == draft.coverData)
        var result2 = result
        let used = result2.use(.cover, on: merged)
        #expect(used.coverData == cover)
        // Without a downloaded cover nothing is offered.
        let (_, none) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: nil, into: draft, locale: locale)
        #expect(!none.offered.contains(.cover))
    }

    @Test func statusDatesRatingNotesAndCollectionsAreUntouched() throws {
        var draft = editDraft()
        draft.status = .read
        draft.startedAt = date(2026, 1, 2)
        draft.finishedAt = date(2026, 2, 3)
        draft.rating = 4
        draft.notes = "Disturbing."
        draft.collectionIDs = [UUID(), UUID()]
        let (merged, _) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: cover, into: draft, locale: locale)
        #expect(merged.status == draft.status)
        #expect(merged.startedAt == draft.startedAt && merged.finishedAt == draft.finishedAt)
        #expect(merged.rating == draft.rating && merged.notes == draft.notes)
        #expect(merged.collectionIDs == draft.collectionIDs)
    }

    // MARK: Display

    @Test func useTakesTheValueAndHidesTheNote() throws {
        let (merged, original) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: nil, into: editDraft(), locale: locale)
        var result = original
        let after = result.use(.year, on: merged)
        #expect(after.yearText == "2009")
        #expect(!result.showsOffer(.year, in: after))
        #expect(result.showsOffer(.pages, in: after))
        #expect(result.isHighlighted(.year, in: after))
        #expect(result.used == [.year])
    }

    @Test func editingAFilledFieldRemovesItsHighlight() throws {
        let (merged, result) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: nil, into: editDraft(), locale: locale)
        #expect(result.isHighlighted(.subtitle, in: merged))
        #expect(!result.isHighlighted(.year, in: merged))
        var edited = merged
        edited.subtitle = "Roman."
        #expect(!result.isHighlighted(.subtitle, in: edited))
        #expect(result.hasHighlight(in: edited))
        edited.subtitle = merged.subtitle
        #expect(result.isHighlighted(.subtitle, in: edited))
    }

    @Test func editingTheOfferedFieldToTheFoundValueHidesTheNote() throws {
        let (merged, result) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: nil, into: editDraft(), locale: locale)
        var edited = merged
        edited.pagesText = "173"
        #expect(!result.showsOffer(.pages, in: edited))
    }

    @Test func undoRestoresEveryFilledAndUsedField() throws {
        let before = editDraft()
        let (merged, merge) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: cover, into: before, locale: locale)
        var result = merge
        let used = result.use(.year, on: merged)
        let undone = result.undo(on: used)
        #expect(undone == before)
        // A typed edit to a field Complete did not touch survives.
        var typed = used
        typed.notes = "typed after"
        #expect(result.undo(on: typed).notes == "typed after")
    }

    @Test func undoRemovesACoverTheUserDidNotHave() throws {
        let (merged, result) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: cover, into: BookDraft(), locale: locale)
        #expect(merged.coverData == cover)
        #expect(result.undo(on: merged).coverData == nil)
    }

    @Test func everythingMatchingGivesZeroCounts() throws {
        let record = try piercing()
        let (filled, _) = LookupResult.merge(record, authors: recordAuthors, cover: nil, into: BookDraft(), locale: locale)
        let (_, again) = LookupResult.merge(record, authors: recordAuthors, cover: nil, into: filled, locale: locale)
        #expect(again.filledCount == 0 && again.differCount == 0)
        #expect(!again.hasHighlight(in: filled))
    }

    @Test func valuesTypedDuringTheLookupWin() throws {
        // The merge runs against the draft as it is when the result arrives.
        var draft = BookDraft()
        draft.publisher = "Typed Verlag"
        let (merged, result) = LookupResult.merge(try piercing(), authors: recordAuthors, cover: nil, into: draft, locale: locale)
        #expect(merged.publisher == "Typed Verlag")
        #expect(result.offered.contains(.publisher))
    }
}
