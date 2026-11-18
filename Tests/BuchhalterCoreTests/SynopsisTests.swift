import Foundation
import SwiftData
import Testing
@testable import BuchhalterCore

struct SynopsisTextTests {
    @Test func dnbBlurbPageBecomesItsParagraph() throws {
        let html = try #require(String(data: fixture("dnb-blurb-piercing.html"), encoding: .utf8))
        let text = try #require(SynopsisText.plain(fromHTML: html))
        #expect(text.hasPrefix("In einer schlaflosen Nacht steht der junge Grafikdesigner Kawashima"))
        #expect(text.hasSuffix("neu verteilt."))
        #expect(!text.contains("<") && !text.contains("\n"))
    }

    @Test func breaksAndBlocksBecomeParagraphs() {
        let text = SynopsisText.plain(fromHTML: "<p>One <b>bold</b>.</p><p>Two<br>lines</p><br><br>Three")
        #expect(text == "One bold.\n\nTwo\nlines\n\nThree")
    }

    @Test func entitiesDecode() {
        #expect(SynopsisText.plain(fromHTML: "A &amp; B &quot;c&quot; it&#8217;s &#x2013; &auml; &bogus; &") == "A & B \"c\" it’s – ä &bogus; &")
    }

    @Test func emptyTextIsNil() {
        #expect(SynopsisText.plain(fromHTML: "  <p> </p>\n<br>") == nil)
        #expect(SynopsisText.cleanedSummary("Zusammenfassung:  ") == nil)
    }

    @Test func summaryLosesPrefixAndPublisherNote() {
        let summary = "Zusammenfassung: Chronicles the decline of a German merchant clan.--(Provided by publisher.)"
        #expect(SynopsisText.cleanedSummary(summary) == "Chronicles the decline of a German merchant clan.")
    }
}

struct SynopsisSourceTests {
    @Test func dnbRecordLinksTheBlurb() throws {
        let parsed = try MARCXMLParser.parse(fixture("dnb-isbn-piercing.xml"))
        let record = try #require(parsed.records.compactMap(DNBRecordMapper.record(from:)).first)
        #expect(record.synopsis == .dnbBlurb(try #require(URL(string: "https://services.dnb.de/plus/idn/991442512/blurb/"))))
        #expect(record.synopsisLanguage == record.language)
    }

    @Test func olderDNBLinksCountAndOthersDoNot() throws {
        func record(_ url: String, label: String = "Inhaltstext") throws -> SynopsisReference? {
            let link = MARCDataField(tag: "856", ind1: "4", ind2: "2", subfields: [
                MARCSubfield(code: "u", value: url), MARCSubfield(code: "3", value: label),
            ])
            return DNBRecordMapper.synopsis(in: MARCRecord(controlFields: ["001": "1"], dataFields: [link]))
        }
        let deposit = "http://deposit.dnb.de/cgi-bin/dokserv?id=123&prov=M&dok_var=1&dok_ext=htm"
        guard case .dnbBlurb(let url)? = try record(deposit) else { Issue.record("no blurb"); return }
        #expect(url.scheme == "https" && url.host == "deposit.dnb.de")
        #expect(try record("https://d-nb.info/123/04") != nil)
        #expect(try record("https://example.com/blurb") == nil)
        #expect(try record("https://d-nb.info/123/04", label: "Inhaltsverzeichnis") == nil)
    }

    @Test func dnbBlurbThatIsAPDFIsNone() async throws {
        let pdf = DNBService(client: FakeHTTPClient(data: Data("%PDF-1.4 …".utf8)))
        #expect(await pdf.synopsis(for: .dnbBlurb(try #require(URL(string: "https://d-nb.info/1/04")))) == nil)
    }

    @Test func dnbSummaryWithoutBlurbIsText() throws {
        let parsed = try MARCXMLParser.parse(fixture("dnb-buddenbrooks-mann.xml"))
        let records = parsed.records.compactMap(DNBRecordMapper.record(from:))
        let withSummary = try #require(records.first { if case .text = $0.synopsis { true } else { false } })
        guard case .text(let text) = withSummary.synopsis else { return }
        #expect(!text.hasPrefix("Zusammenfassung"))
    }

    @Test func dnbDownloadsTheBlurb() async throws {
        let blurb = try #require(URL(string: "https://services.dnb.de/plus/idn/991442512/blurb/"))
        let ok = DNBService(client: FakeHTTPClient(data: fixture("dnb-blurb-piercing.html")))
        #expect(await ok.synopsis(for: .dnbBlurb(blurb))?.hasPrefix("In einer schlaflosen Nacht") == true)
        let missing = DNBService(client: FakeHTTPClient(data: Data(), status: 404))
        #expect(await missing.synopsis(for: .dnbBlurb(blurb)) == nil)
        let offline = DNBService(client: FakeHTTPClient { _ in throw URLError(.timedOut) })
        #expect(await offline.synopsis(for: .dnbBlurb(blurb)) == nil)
    }

    @Test func openLibraryWorkURL() throws {
        let url = try #require(OpenLibraryService.workURL(for: "/works/OL3511459W"))
        #expect(url.absoluteString == "https://openlibrary.org/works/OL3511459W.json")
        #expect(OpenLibraryService.workURL(for: "/books/OL1M") == nil)
        #expect(OpenLibraryService.workURL(for: "/works/../x") == nil)
    }

    @Test func openLibrarySearchSetsWorkReference() async throws {
        let service = OpenLibraryService(client: FakeHTTPClient(data: fixture("openlibrary-stoner-williams.json")))
        let response = try await service.search(.titleAuthor(title: "Stoner", authors: [AuthorDraft(name: "John Williams", sortName: "Williams, John")]))
        let record = try #require(response.records.first)
        #expect(record.synopsis == .openLibraryWork(key: "/works/OL3511459W"))
        #expect(record.synopsisLanguage == nil)
    }

    @Test func openLibraryDescriptionAsObjectAndString() async throws {
        let object = OpenLibraryService(client: FakeHTTPClient(data: fixture("openlibrary-work-stoner.json")))
        #expect(await object.synopsis(for: .openLibraryWork(key: "/works/OL3511459W"))?.hasPrefix("William Stoner is born") == true)
        let string = OpenLibraryService(client: FakeHTTPClient(data: Data(#"{"description": "  Plain  text. "}"#.utf8)))
        #expect(await string.synopsis(for: .openLibraryWork(key: "/works/OL1W")) == "Plain text.")
        let none = OpenLibraryService(client: FakeHTTPClient(data: Data(#"{"title": "x"}"#.utf8)))
        #expect(await none.synopsis(for: .openLibraryWork(key: "/works/OL1W")) == nil)
    }

    @Test func googleDescriptionBecomesPlainText() throws {
        let list = try JSONDecoder().decode(GoogleBooksRecordMapper.VolumeList.self, from: fixture("googlebooks-description.json"))
        let record = try #require(GoogleBooksRecordMapper.records(from: list).first)
        #expect(record.synopsis == .text("A quiet story about a garden & the people who keep it.\n\nSecond paragraph.\nWith a line break – and an em dash."))
        #expect(record.synopsisLanguage == "en")
        let url = GoogleBooksService.url(for: .titleAuthor(title: "The Garden", authors: [AuthorDraft(name: "Nick Newman", sortName: "Newman, Nick")]))
        #expect(url.absoluteString.contains("description"))
    }
}

struct FindSynopsisTests {
    private let query = LookupQuery.titleAuthor(
        title: "Buddenbrooks", authors: [AuthorDraft(name: "Thomas Mann", sortName: "Mann, Thomas")]
    )

    private func record(_ source: LookupSource, language: String?, synopsis: SynopsisReference?, id: String? = nil) -> LookupRecord {
        var record = makeRecord("Buddenbrooks", language: language, source: source, id: id)
        record.synopsis = synopsis
        return record
    }

    @Test func firstRecordInTheBooksLanguageAsksNobodyElse() async throws {
        let dnb = FakeLookupService(.dnb, records: [record(.dnb, language: "de", synopsis: .text("Andere"))])
        let first = record(.dnb, language: "de", synopsis: .text("Deutsch"), id: "dnb:1")
        let found = try await BookLookup(services: [dnb]).findSynopsis([query], first: first, bookLanguage: "de")
        #expect(found == Synopsis(text: "Deutsch", source: .dnb))
        #expect(dnb.searchCount == 0)
    }

    @Test func germanBookSkipsEnglishText() async throws {
        let google = FakeLookupService(.googleBooks, records: [record(.googleBooks, language: "en", synopsis: .text("English"))])
        let dnb = FakeLookupService(.dnb, records: [record(.dnb, language: "de", synopsis: .text("Deutsch"))])
        let found = try await BookLookup(services: [google, dnb]).findSynopsis([query], bookLanguage: "de")
        #expect(found == Synopsis(text: "Deutsch", source: .dnb))
    }

    @Test func onlyAnotherLanguageIsTaken() async throws {
        let google = FakeLookupService(.googleBooks, records: [record(.googleBooks, language: "en", synopsis: .text("English"))])
        let found = try await BookLookup(services: [google]).findSynopsis([query], bookLanguage: "de")
        #expect(found == Synopsis(text: "English", source: .googleBooks))
    }

    @Test func untaggedOpenLibraryLosesToATaggedMatchAndWinsAlone() async throws {
        let ol = FakeLookupService(
            .openLibrary, records: [record(.openLibrary, language: "de", synopsis: .openLibraryWork(key: "/works/OL1W"))],
            synopses: ["/works/OL1W": "Work text"]
        )
        let dnb = FakeLookupService(.dnb, records: [record(.dnb, language: "de", synopsis: .text("Deutsch"))])
        let both = try await BookLookup(services: [ol, dnb]).findSynopsis([query], bookLanguage: "de")
        #expect(both == Synopsis(text: "Deutsch", source: .dnb))
        let alone = try await BookLookup(services: [ol]).findSynopsis([query], bookLanguage: "de")
        #expect(alone == Synopsis(text: "Work text", source: .openLibrary))
    }

    @Test func bookWithoutLanguageTakesTheFirst() async throws {
        let google = FakeLookupService(.googleBooks, records: [record(.googleBooks, language: "en", synopsis: .text("English"))])
        let dnb = FakeLookupService(.dnb, records: [record(.dnb, language: "de", synopsis: .text("Deutsch"))])
        let found = try await BookLookup(services: [google, dnb]).findSynopsis([query], bookLanguage: nil)
        #expect(found?.source == .googleBooks)
        #expect(dnb.searchCount == 0)
    }

    @Test func unreachableEverywhereThrows() async {
        let dnb = FakeLookupService(.dnb, failing: LookupError.unreachable(.dnb))
        await #expect(throws: LookupError.noSourceReached([.dnb])) {
            try await BookLookup(services: [dnb]).findSynopsis([query], bookLanguage: "de")
        }
    }

    @Test func nothingFoundIsNil() async throws {
        let dnb = FakeLookupService(.dnb, records: [record(.dnb, language: "de", synopsis: nil)])
        #expect(try await BookLookup(services: [dnb]).findSynopsis([query], bookLanguage: "de") == nil)
    }

    @Test func atMostThreeCandidatesPerSource() async throws {
        let records = (1...5).map { record(.dnb, language: "en", synopsis: .openLibraryWork(key: "/works/OL\($0)W"), id: "dnb:\($0)") }
        let dnb = FakeLookupService(.dnb, records: records)
        _ = try await BookLookup(services: [dnb]).findSynopsis([query], bookLanguage: "de")
        #expect(dnb.synopsisCount == BookLookup.maximumSynopsisCandidates)
    }
}

struct SynopsisMergeTests {
    private func merge(_ draft: BookDraft, synopsis: Synopsis?) -> (draft: BookDraft, result: LookupResult) {
        LookupResult.merge(makeRecord("Buddenbrooks"), authors: [], cover: nil, synopsis: synopsis, into: draft)
    }

    private var draft: BookDraft {
        var draft = BookDraft()
        draft.title = "Buddenbrooks"
        return draft
    }

    @Test func emptySynopsisIsFilledAndCounted() {
        let merged = merge(draft, synopsis: Synopsis(text: "Text", source: .dnb))
        #expect(merged.draft.synopsis == "Text" && merged.draft.synopsisSource == .dnb)
        #expect(merged.result.filled.contains(.synopsis))
        #expect(merged.result.isHighlighted(.synopsis, in: merged.draft))
        let undone = merged.result.undo(on: merged.draft)
        #expect(undone.synopsis.isEmpty && undone.synopsisSource == nil)
    }

    @Test func sameTextIsNeitherFilledNorOffered() {
        var mine = draft
        mine.synopsis = "Ein  Text\nüber Lübeck."
        let merged = merge(mine, synopsis: Synopsis(text: "ein text über lübeck.", source: .dnb))
        #expect(!merged.result.filled.contains(.synopsis) && !merged.result.offered.contains(.synopsis))
    }

    @Test func differentTextIsOfferedAndUsed() {
        var mine = draft
        mine.synopsis = "Mine"
        var merged = merge(mine, synopsis: Synopsis(text: "Theirs", source: .googleBooks))
        #expect(merged.draft.synopsis == "Mine")
        #expect(merged.result.showsOffer(.synopsis, in: merged.draft))
        #expect(merged.result.offeredSynopsisSource == .googleBooks)
        let used = merged.result.use(.synopsis, on: merged.draft)
        #expect(used.synopsis == "Theirs" && used.synopsisSource == .googleBooks)
    }
}

@MainActor
struct SynopsisStoreTests {
    @Test func addAndUpdateStoreTextAndSource() throws {
        let t = try TestLibrary()
        var draft = BookDraft()
        draft.title = "Piercing"
        draft.synopsis = "  Ein Text.  "
        draft.synopsisSource = .dnb
        let book = try t.library.addBook(draft)
        #expect(book.synopsis == "Ein Text." && book.synopsisSource == .dnb)
        var edited = BookDraft(book: book)
        #expect(edited.synopsis == "Ein Text." && edited.synopsisSource == .dnb)
        edited.synopsis = "Mein Text."
        edited.synopsisSource = nil
        try t.library.updateBook(book, with: edited)
        #expect(book.synopsis == "Mein Text." && book.synopsisSource == nil)
        edited.synopsis = " "
        edited.synopsisSource = .dnb
        try t.library.updateBook(book, with: edited)
        #expect(book.synopsis == nil && book.synopsisSourceRaw == nil)
    }

    @Test func setSynopsisIsOneUndoStep() throws {
        let t = try TestLibrary(undo: true)
        let book = try t.add("Stoner")
        let undo = try #require(t.undo)
        try t.library.setSynopsis("A text.", source: .googleBooks, for: book)
        #expect(book.synopsis == "A text." && book.synopsisSource == .googleBooks)
        #expect(undo.undoActionName == "Find Synopsis")
        undo.undo()
        t.context.processPendingChanges()
        #expect(book.synopsis == nil && book.synopsisSourceRaw == nil)
        undo.redo()
        t.context.processPendingChanges()
        #expect(book.synopsis == "A text." && book.synopsisSource == .googleBooks)
        try t.library.setSynopsis(nil, source: nil, for: book)
        #expect(undo.undoActionName == "Remove Synopsis")
        undo.undo()
        t.context.processPendingChanges()
        #expect(book.synopsis == "A text.")
    }

    @Test func v2StoreOpensAsV3() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: LibraryLocation.storeFileName)
        let bookID = UUID()
        do {
            let schema = Schema(versionedSchema: SchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let book = SchemaV2.Book()
            book.id = bookID
            book.title = "Buddenbrooks"
            book.publisher = "Fischer"
            container.mainContext.insert(book)
            let reading = SchemaV2.Reading()
            reading.stars = 4.5
            container.mainContext.insert(reading)
            reading.book = book
            try container.mainContext.save()
        }
        let container = try LibraryContainer.make(at: url)
        let book = try #require(Library(context: container.mainContext).fetchBooks().first)
        #expect(book.id == bookID && book.title == "Buddenbrooks" && book.publisher == "Fischer")
        #expect(book.readings?.first?.stars == 4.5)
        #expect(book.synopsis == nil && book.synopsisSourceRaw == nil)
    }
}
