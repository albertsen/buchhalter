import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BuchhalterCore

struct BookLookupTests {
    private func titleQuery(_ title: String, _ author: String) -> LookupQuery {
        .titleAuthor(title: title, authors: [AuthorDraft(name: author, sortName: AuthorName.guessSortName(author))])
    }

    private func isbnQuery(_ text: String) throws -> LookupQuery {
        guard case .valid(let isbn) = ISBN.parse(text) else { throw CocoaError(.fileReadCorruptFile) }
        return .isbn(isbn, display: text)
    }

    private func queryValue(_ url: URL) throws -> String {
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return try #require(items.first { $0.name == "query" }?.value)
    }

    // MARK: DNB URLs

    @Test func dnbTitleAndAuthorURL() throws {
        let url = DNBService.url(for: titleQuery("Buddenbrooks", "Thomas Mann"))
        #expect(url.host == "services.dnb.de" && url.path == "/sru/dnb")
        #expect(try queryValue(url) == "tit=Buddenbrooks and per=Mann and mat=books")
        // The raw query escapes "=" and spaces.
        let raw = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
        #expect(raw.contains("query=tit%3DBuddenbrooks%20and%20per%3DMann%20and%20mat%3Dbooks"))
        #expect(raw.contains("maximumRecords=100"))
        #expect(raw.contains("recordSchema=MARC21-xml"))
        #expect(raw.contains("operation=searchRetrieve"))
    }

    @Test func dnbSplitsWordsAndStripsCQLCharacters() throws {
        let url = DNBService.url(for: titleQuery("Der \"Zauberberg\" (Roman) = a/b*", "Thomas Mann"))
        #expect(try queryValue(url) == "tit=Der and tit=Zauberberg and tit=Roman and tit=a and tit=b and per=Mann and mat=books")
        // CQL operators inside a title must not become operators.
        let operators = DNBService.url(for: titleQuery("Pride and Prejudice", "Jane Austen"))
        #expect(try queryValue(operators) == "tit=Pride and tit=Prejudice and per=Austen and mat=books")
    }

    @Test func dnbSurnameComesFromTheSortName() throws {
        let authors = [AuthorDraft(name: "Ursula K. Le Guin", sortName: "Le Guin, Ursula K.")]
        let url = DNBService.url(for: .titleAuthor(title: "Earthsea", authors: authors))
        #expect(try queryValue(url) == "tit=Earthsea and per=Le and per=Guin and mat=books")
        let noComma = DNBService.url(for: .titleAuthor(title: "Stoner", authors: [AuthorDraft(name: "John Williams", sortName: "Williams")]))
        #expect(try queryValue(noComma) == "tit=Stoner and per=Williams and mat=books")
    }

    @Test func dnbISBNURL() throws {
        let url = DNBService.url(for: try isbnQuery("978-3-935890-59-5"))
        #expect(try queryValue(url) == "num=9783935890595")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery?.contains("maximumRecords=10&") == true)
    }

    @Test func dnbURLEscapesNonASCII() {
        let url = DNBService.url(for: titleQuery("Die Verwandlung für Ärzte", "Franz Kafka"))
        let allASCII = url.absoluteString.allSatisfy { $0.isASCII }
        #expect(allASCII)
    }

    // MARK: DNB service

    @Test func dnbServiceFetchesParsesAndFilters() async throws {
        let client = FakeHTTPClient(data: fixture("dnb-buddenbrooks-mann.xml"))
        let service = DNBService(client: client)
        let response = try await service.search(titleQuery("Buddenbrooks", "Thomas Mann"))
        #expect(response.totalCount == 477)
        #expect(response.records.count == 19)
        #expect(await client.requested.count == 1)
    }

    @Test func userAgentNamesTheApp() {
        #expect(URLSessionHTTPClient.userAgent == "Buchhalter/0.1 (personal book app)")
        #expect(!URLSessionHTTPClient.userAgent.contains("@"))
    }

    @Test func dnbFailuresAreUnreachable() async {
        let query = titleQuery("A", "B C")
        for client in [
            FakeHTTPClient(data: Data(), status: 500),
            FakeHTTPClient(data: Data("<html>".utf8)),
            FakeHTTPClient { _ in throw URLError(.timedOut) },
        ] {
            await #expect(throws: LookupError.unreachable(.dnb)) { try await DNBService(client: client).search(query) }
        }
        let diagnostic = Data("""
        <searchRetrieveResponse xmlns="http://www.loc.gov/zing/srw/"><numberOfRecords>0</numberOfRecords>\
        <diagnostics><diagnostic><message>bad</message></diagnostic></diagnostics></searchRetrieveResponse>
        """.utf8)
        await #expect(throws: LookupError.unreachable(.dnb)) { try await DNBService(client: FakeHTTPClient(data: diagnostic)).search(query) }
    }

    @Test func dnbCoverURLsAndChecks() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let client = FakeHTTPClient { url in
            url.absoluteString.hasSuffix("&size=l") ? (png, 200) : (Data("<html>not found</html>".utf8), 404)
        }
        let service = DNBService(client: client)
        #expect(await service.coverData(for: .dnb(isbn13: "9783935890595"), size: .large) == png)
        #expect(await service.coverData(for: .dnb(isbn13: "9783935890595"), size: .small) == nil)
        let urls = await client.requested.map(\.absoluteString)
        #expect(urls.contains("https://portal.dnb.de/opac/mvb/cover?isbn=9783935890595&size=l"))
        // A 200 with an HTML body is no cover either.
        let html = DNBService(client: FakeHTTPClient(data: Data("<html></html>".utf8)))
        #expect(await html.coverData(for: .dnb(isbn13: "9783935890595"), size: .large) == nil)
        let offline = DNBService(client: FakeHTTPClient { _ in throw URLError(.notConnectedToInternet) })
        #expect(await offline.coverData(for: .dnb(isbn13: "9783935890595"), size: .large) == nil)
    }

    // MARK: Coordinator

    private func lookup(_ primary: FakeLookupService, _ fallback: FakeLookupService) -> BookLookup {
        BookLookup(primary: primary, fallback: fallback)
    }

    private let query = LookupQuery.titleAuthor(
        title: "Buddenbrooks", authors: [AuthorDraft(name: "Thomas Mann", sortName: "Mann, Thomas")]
    )

    @Test func oneMatchIsSingle() async throws {
        let dnb = FakeLookupService(.dnb, records: [makeRecord("Buddenbrooks"), makeRecord("Other book")])
        let ol = FakeLookupService(.openLibrary)
        let outcome = try await lookup(dnb, ol).run(query, preferredLanguage: "de") { _ in }
        guard case .single(let record) = outcome else { Issue.record("expected single"); return }
        #expect(record.title == "Buddenbrooks")
        #expect(ol.searchCount == 0)
    }

    @Test func severalMatchesAreOrderedAndTruncationFollowsTheTotal() async throws {
        let records = [
            makeRecord("Buddenbrooks", year: 2010, id: "old"), makeRecord("Buddenbrooks", year: 2026, id: "new"),
        ]
        let few = try await lookup(FakeLookupService(.dnb, records: records, total: 2), FakeLookupService(.openLibrary))
            .run(query, preferredLanguage: "de") { _ in }
        guard case .several(let list) = few else { Issue.record("expected several"); return }
        #expect(list.records.map(\.id) == ["new", "old"])
        #expect(list.source == .dnb)
        #expect(!list.isTruncated)
        let many = try await lookup(FakeLookupService(.dnb, records: records, total: 477), FakeLookupService(.openLibrary))
            .run(query, preferredLanguage: "de") { _ in }
        guard case .several(let truncated) = many else { Issue.record("expected several"); return }
        #expect(truncated.isTruncated && truncated.totalCount == 477)
        let exactly = try await lookup(FakeLookupService(.dnb, records: records, total: 100), FakeLookupService(.openLibrary))
            .run(query, preferredLanguage: "de") { _ in }
        if case .several(let list) = exactly { #expect(!list.isTruncated) }
    }

    @Test func zeroMatchesOnDNBAsksOpenLibrary() async throws {
        let dnb = FakeLookupService(.dnb, records: [makeRecord("Unrelated")])
        let ol = FakeLookupService(.openLibrary, records: [makeRecord("Buddenbrooks", source: .openLibrary)])
        let asked = SourceLog()
        let outcome = try await lookup(dnb, ol).run(query, preferredLanguage: nil) { source in asked.add(source) }
        guard case .single(let record) = outcome else { Issue.record("expected single"); return }
        #expect(record.source == .openLibrary)
        #expect(asked.sources == [.openLibrary])
        #expect(dnb.searchCount == 1 && ol.searchCount == 1)
    }

    @Test func zeroOnBothIsNone() async throws {
        let outcome = try await lookup(FakeLookupService(.dnb), FakeLookupService(.openLibrary))
            .run(query, preferredLanguage: nil) { _ in }
        guard case .none = outcome else { Issue.record("expected none"); return }
    }

    @Test func dnbFailureDoesNotFallBack() async {
        let ol = FakeLookupService(.openLibrary, records: [makeRecord("Buddenbrooks", source: .openLibrary)])
        let dnb = FakeLookupService(.dnb, failing: LookupError.unreachable(.dnb))
        await #expect(throws: LookupError.unreachable(.dnb)) {
            try await lookup(dnb, ol).run(query, preferredLanguage: nil) { _ in }
        }
        #expect(ol.searchCount == 0)
    }

    @Test func openLibraryFailureIsReportedForOpenLibrary() async {
        let dnb = FakeLookupService(.dnb)
        let ol = FakeLookupService(.openLibrary, failing: LookupError.unreachable(.openLibrary))
        await #expect(throws: LookupError.unreachable(.openLibrary)) {
            try await lookup(dnb, ol).run(query, preferredLanguage: nil) { _ in }
        }
    }

    @Test func cancellingStopsTheLookup() async {
        let dnb = FakeLookupService(.dnb, records: [makeRecord("Buddenbrooks")], delay: .seconds(30))
        let coordinator = lookup(dnb, FakeLookupService(.openLibrary))
        let query = query
        let task = Task { try await coordinator.run(query, preferredLanguage: nil) { _ in } }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: Covers

    private func makePNG(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func coverIsNormalizedToJPEG() async throws {
        let png = try makePNG(width: 2400, height: 1600)
        let dnb = FakeLookupService(.dnb, covers: [.large: png])
        let data = try #require(await lookup(dnb, FakeLookupService(.openLibrary)).cover(for: makeRecord("A", isbn: ["9783935890595"])))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        #expect(max(width, height) <= 1200)
    }

    @Test func coverFailuresGiveNil() async {
        let dnb = FakeLookupService(.dnb, covers: [.large: Data("<html>".utf8)])
        let coordinator = lookup(dnb, FakeLookupService(.openLibrary))
        // Bytes that are not an image cannot be normalized.
        #expect(await coordinator.cover(for: makeRecord("A", isbn: ["9783935890595"])) == nil)
        // No cover reference at all.
        #expect(await coordinator.cover(for: makeRecord("A")) == nil)
        // The service has none.
        let none = lookup(FakeLookupService(.dnb), FakeLookupService(.openLibrary))
        #expect(await none.cover(for: makeRecord("A", isbn: ["9783935890595"])) == nil)
    }

    // MARK: Find Cover

    @Test func findCoverTakesTheFirstMatchWithACover() async throws {
        let png = try makePNG(width: 300, height: 450)
        let dnb = FakeLookupService(.dnb, records: [makeRecord("Buddenbrooks", isbn: ["9783935890595"])], covers: [.large: png])
        let data = try await lookup(dnb, FakeLookupService(.openLibrary)).findCover([query], preferredLanguage: "de")
        #expect(data != nil)
    }

    @Test func findCoverFallsBackWhenDNBHasNoCover() async throws {
        let png = try makePNG(width: 300, height: 450)
        // DNB matches, but its cover service answers with nothing.
        let dnb = FakeLookupService(.dnb, records: [makeRecord("Buddenbrooks", isbn: ["9783935890595"])])
        let ol = FakeLookupService(.openLibrary, records: [
            LookupRecord(id: "openlibrary:x", source: .openLibrary, title: "Buddenbrooks",
                         authors: [LookupAuthor(name: "Thomas Mann")], cover: .openLibrary(coverID: 1)),
        ], covers: [.large: png])
        let data = try await lookup(dnb, ol).findCover([query], preferredLanguage: "de")
        #expect(data != nil)
        #expect(ol.searchCount == 1)
    }

    @Test func findCoverFallsBackWhenDNBIsUnreachable() async throws {
        let png = try makePNG(width: 300, height: 450)
        let dnb = FakeLookupService(.dnb, failing: LookupError.unreachable(.dnb))
        let ol = FakeLookupService(.openLibrary, records: [
            LookupRecord(id: "openlibrary:x", source: .openLibrary, title: "Buddenbrooks",
                         authors: [LookupAuthor(name: "Thomas Mann")], cover: .openLibrary(coverID: 1)),
        ], covers: [.large: png])
        #expect(try await lookup(dnb, ol).findCover([query], preferredLanguage: "de") != nil)
    }

    @Test func findCoverWithoutAnyCoverIsNil() async throws {
        let dnb = FakeLookupService(.dnb, records: [makeRecord("Buddenbrooks")])
        #expect(try await lookup(dnb, FakeLookupService(.openLibrary)).findCover([query], preferredLanguage: nil) == nil)
    }

    @Test func findCoverUsesTheWorkCoverWhenTheEditionHasNone() async throws {
        let png = try makePNG(width: 300, height: 450)
        let ol = FakeLookupService(.openLibrary, records: [
            LookupRecord(id: "openlibrary:x", source: .openLibrary, title: "Buddenbrooks",
                         authors: [LookupAuthor(name: "Thomas Mann")], workCover: .openLibrary(coverID: 2)),
        ], covers: [.large: png])
        #expect(try await lookup(FakeLookupService(.dnb), ol).findCover([query], preferredLanguage: nil) != nil)
    }

    @Test func findCoverTriesTheNextQuery() async throws {
        let png = try makePNG(width: 300, height: 450)
        // The ISBN search matches nothing; the title search finds a cover.
        let isbn = try isbnQuery("9783935890595")
        let dnb = FakeLookupService(.dnb, records: [makeRecord("Buddenbrooks", isbn: ["9783935890596"])], covers: [.large: png])
        #expect(try await lookup(dnb, FakeLookupService(.openLibrary)).findCover([isbn, query], preferredLanguage: nil) != nil)
        #expect(dnb.searchCount == 2)
    }

    @Test func coverQueriesCutTheTitleAndKeepTheISBNFirst() {
        var draft = BookDraft()
        draft.title = "Galveston: A Novel"
        draft.authors = [AuthorDraft(name: "Nic Pizzolatto", sortName: "Pizzolatto, Nic")]
        draft.isbnText = "9783935890595"
        let queries = LookupQuery.coverQueries(for: draft)
        #expect(queries.count == 2)
        if case .isbn = queries.first {} else { Issue.record("ISBN first") }
        if case .titleAuthor(let title, _)? = queries.last { #expect(title == "Galveston") } else { Issue.record("title second") }
        draft.title = "On the Road (Penguin 20th Century Classics)"
        draft.isbnText = ""
        if case .titleAuthor(let title, _)? = LookupQuery.coverQueries(for: draft).first {
            #expect(title == "On the Road")
        } else { Issue.record("title query") }
    }

    @Test func findCoverThrowsWhenNoSourceIsReachable() async {
        let dnb = FakeLookupService(.dnb, failing: LookupError.unreachable(.dnb))
        let ol = FakeLookupService(.openLibrary, failing: LookupError.unreachable(.openLibrary))
        await #expect(throws: LookupError.unreachable(.dnb)) {
            try await self.lookup(dnb, ol).findCover([self.query], preferredLanguage: nil)
        }
    }

    @Test func coversAreFetchedFromTheRecordsOwnSource() async throws {
        let png = try makePNG(width: 100, height: 150)
        let ol = FakeLookupService(.openLibrary, covers: [.large: png])
        let coordinator = lookup(FakeLookupService(.dnb), ol)
        let record = LookupRecord(id: "openlibrary:x", source: .openLibrary, title: "A", cover: .openLibrary(coverID: 1))
        #expect(await coordinator.cover(for: record) != nil)
    }
}

/// Collects the sources `run` reported, from a `@Sendable` closure.
final class SourceLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [LookupSource] = []
    func add(_ source: LookupSource) { lock.withLock { values.append(source) } }
    var sources: [LookupSource] { lock.withLock { values } }
}
