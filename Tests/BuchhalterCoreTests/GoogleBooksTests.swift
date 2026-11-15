import Foundation
import Testing
@testable import BuchhalterCore

struct GoogleBooksTests {
    private static let testKey = "test-key-123456"

    private func titleQuery(_ title: String, _ author: String) -> LookupQuery {
        .titleAuthor(title: title, authors: [AuthorDraft(name: author, sortName: AuthorName.guessSortName(author))])
    }

    private func isbnQuery(_ text: String) throws -> LookupQuery {
        guard case .valid(let isbn) = ISBN.parse(text) else { throw CocoaError(.fileReadCorruptFile) }
        return .isbn(isbn, display: text)
    }

    private func service(
        _ client: FakeHTTPClient, key: String? = GoogleBooksTests.testKey
    ) -> GoogleBooksService {
        GoogleBooksService(keys: FakeSecretStore(key), client: client)
    }

    private func rawQuery(_ url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
    }

    // MARK: URLs

    @Test func isbnURL() throws {
        let url = GoogleBooksService.url(for: try isbnQuery("978-1-80499-375-0"))
        #expect(url.host == "www.googleapis.com" && url.path == "/books/v1/volumes")
        let raw = rawQuery(url)
        #expect(raw.hasPrefix("q=isbn:9781804993750&"))
        #expect(raw.contains("printType=books"))
        #expect(raw.contains("maxResults=40"))
        #expect(raw.contains("projection=full"))
        #expect(raw.contains("fields=totalItems%2Citems%28id%2CvolumeInfo%28title"))
    }

    @Test func titleAndAuthorURLUsesOneTermPerWord() {
        let url = GoogleBooksService.url(for: titleQuery("Der Zauberberg", "Thomas Mann"))
        #expect(rawQuery(url).hasPrefix("q=intitle:Der+intitle:Zauberberg+inauthor:Mann&"))
        let guin = GoogleBooksService.url(for: .titleAuthor(
            title: "Earthsea", authors: [AuthorDraft(name: "Ursula K. Le Guin", sortName: "Le Guin, Ursula K.")]
        ))
        #expect(rawQuery(guin).hasPrefix("q=intitle:Earthsea+inauthor:Le+inauthor:Guin&"))
    }

    @Test func urlsEncodeNonASCIIAndPlusSigns() {
        let umlaut = GoogleBooksService.url(for: titleQuery("Die Verwandlung für Ärzte", "Franz Kafka"))
        #expect(rawQuery(umlaut).contains("intitle:f%C3%BCr") || rawQuery(umlaut).contains("intitle:F%C3%BCr"))
        #expect(umlaut.absoluteString.allSatisfy { $0.isASCII })
        // A "+" in the user's text must not split a term.
        let plus = GoogleBooksService.url(for: titleQuery("C++ Primer", "Stanley Lippman"))
        #expect(rawQuery(plus).hasPrefix("q=intitle:C%2B%2B+intitle:Primer+inauthor:Lippman&"))
    }

    @Test func noURLCarriesAKey() throws {
        let urls = [
            GoogleBooksService.url(for: try isbnQuery("9781804993750")),
            GoogleBooksService.url(for: titleQuery("Stoner", "John Williams")),
            GoogleBooksService.volumeURL(id: "xCVQ0QEACAAJ"),
        ]
        for url in urls {
            #expect(!url.absoluteString.lowercased().contains("key"))
        }
    }

    // MARK: Header and key

    @Test func theKeyGoesInTheHeaderNotTheURL() async throws {
        let client = FakeHTTPClient(data: fixture("googlebooks-isbn-garden.json"))
        _ = try await service(client).search(try isbnQuery("9781804993750"))
        let headers = await client.requestedHeaders
        let urls = await client.requested
        #expect(headers == [["X-goog-api-key": Self.testKey]])
        #expect(urls.count == 1)
        #expect(!urls[0].absoluteString.contains(Self.testKey))
    }

    @Test func aMissingOrFailingKeyIsUnreachableAndSendsNothing() async throws {
        let query = try isbnQuery("9781804993750")
        for keys in [FakeSecretStore(nil), FakeSecretStore("", failing: false), FakeSecretStore("x", failing: true)] {
            let client = FakeHTTPClient(data: fixture("googlebooks-isbn-garden.json"))
            await #expect(throws: LookupError.unreachable(.googleBooks)) {
                try await GoogleBooksService(keys: keys, client: client).search(query)
            }
            #expect(await client.requested.isEmpty)
        }
    }

    // MARK: Failure classification

    @Test func rejectedKeyStatusesAreKeyRejected() async throws {
        let query = try isbnQuery("9781804993750")
        for status in [401, 403, 429] {
            let client = FakeHTTPClient(data: Data("{}".utf8), status: status)
            await #expect(throws: LookupError.keyRejected(.googleBooks)) { try await self.service(client).search(query) }
        }
        let quota = FakeHTTPClient(data: fixture("googlebooks-error-quota.json"), status: 429)
        await #expect(throws: LookupError.keyRejected(.googleBooks)) { try await self.service(quota).search(query) }
    }

    @Test func aBadRequestIsKeyRejectedOnlyWhenTheAnswerNamesTheKey() async throws {
        let query = try isbnQuery("9781804993750")
        let invalid = FakeHTTPClient(data: fixture("googlebooks-error-invalid-key.json"), status: 400)
        await #expect(throws: LookupError.keyRejected(.googleBooks)) { try await self.service(invalid).search(query) }
        let reason = FakeHTTPClient(
            data: Data(#"{"error":{"code":400,"message":"x","errors":[{"reason":"keyInvalid"}]}}"#.utf8), status: 400
        )
        await #expect(throws: LookupError.keyRejected(.googleBooks)) { try await self.service(reason).search(query) }
        let malformed = FakeHTTPClient(
            data: Data(#"{"error":{"code":400,"message":"Invalid query","errors":[{"reason":"invalid"}]}}"#.utf8), status: 400
        )
        await #expect(throws: LookupError.unreachable(.googleBooks)) { try await self.service(malformed).search(query) }
        let garbage = FakeHTTPClient(data: Data("<html>".utf8), status: 400)
        await #expect(throws: LookupError.unreachable(.googleBooks)) { try await self.service(garbage).search(query) }
    }

    @Test func otherFailuresAreUnreachableAndCancellationStaysCancellation() async throws {
        let query = try isbnQuery("9781804993750")
        for client in [
            FakeHTTPClient(data: Data(), status: 500),
            FakeHTTPClient(data: Data("<html>".utf8)),
            FakeHTTPClient { _ in throw URLError(.timedOut) },
            FakeHTTPClient { _ in throw URLError(.notConnectedToInternet) },
        ] {
            await #expect(throws: LookupError.unreachable(.googleBooks)) { try await self.service(client).search(query) }
        }
        let cancelled = FakeHTTPClient { _ in throw URLError(.cancelled) }
        await #expect(throws: CancellationError.self) { try await self.service(cancelled).search(query) }
    }

    // MARK: Mapping

    @Test func theGardenMapsEveryField() async throws {
        let client = FakeHTTPClient(data: fixture("googlebooks-isbn-garden.json"))
        let response = try await service(client).search(try isbnQuery("9781804993750"))
        #expect(response.totalCount == 1)
        let record = try #require(response.records.first)
        #expect(record.id == "googlebooks:xCVQ0QEACAAJ")
        #expect(record.source == .googleBooks)
        #expect(record.title == "The Garden")
        #expect(record.authors == [LookupAuthor(name: "Nick Newman")])
        #expect(record.year == 2026)
        #expect(record.language == "en")
        #expect(record.publisher == "Penguin Group")
        #expect(record.isbn13s == ["9781804993750"] && record.isbnDisplay == "9781804993750")
        // Google reports 0 pages for this book: no page count, not "0 pages".
        #expect(record.pages == nil)
        #expect(record.cover == .googleBooks(volumeID: "xCVQ0QEACAAJ"))
        #expect(record.workCover == nil)
        #expect(record.webPage?.scheme == "https")
        #expect(record.webPage?.absoluteString == "https://books.google.com/books/about/The_Garden.html?hl=&id=xCVQ0QEACAAJ")
        // The ISBN match filter keeps it.
        #expect(LookupMatching.matches(response.records, for: try isbnQuery("9781804993750")).count == 1)
    }

    @Test func eBooksAreDroppedAndTheRestKeepsGooglesOrder() async throws {
        let client = FakeHTTPClient(data: fixture("googlebooks-stoner-williams.json"))
        let response = try await service(client).search(titleQuery("Stoner", "John Williams"))
        #expect(response.totalCount == 34)
        // The fixture has 20 volumes, 5 of them e-books.
        #expect(response.records.count == 15)
        #expect(!response.records.contains { $0.id == "googlebooks:KHvRCFRnDv4C" })
        #expect(response.records.first?.id == "googlebooks:pkVFjwEACAAJ")
        // A volume without images has no cover reference; one without authors has none.
        #expect(response.records.first?.cover == nil && response.records.first?.authors.isEmpty == true)
        // A role in brackets is cut off the author's name.
        let turkish = try #require(response.records.first { $0.id == "googlebooks:Y79LAQAACAAJ" })
        #expect(turkish.authors.map(\.name) == ["John Williams"])
        let matches = LookupMatching.matches(response.records, for: titleQuery("Stoner", "John Williams"))
        #expect(matches.count >= 8)
    }

    @Test func magazinesAndVolumesWithoutATitleAreDropped() throws {
        let json = Data("""
        {"totalItems":3,"items":[
         {"id":"a","volumeInfo":{"title":"A Magazine","printType":"MAGAZINE"},"saleInfo":{"isEbook":false}},
         {"id":"b","volumeInfo":{"title":"","printType":"BOOK"}},
         {"id":"c","volumeInfo":{"title":"Real Book","printType":"BOOK","language":"pt-BR","publishedDate":"1890"}}]}
        """.utf8)
        let list = try JSONDecoder().decode(GoogleBooksRecordMapper.VolumeList.self, from: json)
        let records = GoogleBooksRecordMapper.records(from: list)
        #expect(records.map(\.title) == ["Real Book"])
        #expect(records.first?.language == "pt" && records.first?.year == 1890)
    }

    @Test func noMatchGivesNoRecords() async throws {
        let client = FakeHTTPClient(data: fixture("googlebooks-no-match.json"))
        let response = try await service(client).search(try isbnQuery("9789999999991"))
        #expect(response.records.isEmpty && response.totalCount == 0)
    }

    // MARK: Covers

    @Test func theLargestImageLinkIsUsedAsHttpsWithoutTheCurl() throws {
        let links = try JSONDecoder().decode(GoogleBooksRecordMapper.ImageLinks.self, from: Data("""
        {"smallThumbnail":"http://books.google.com/books/content?id=A&zoom=5&edge=curl&source=gbs_api",
         "thumbnail":"http://books.google.com/books/content?id=A&zoom=1&edge=curl&source=gbs_api",
         "medium":"http://books.google.com/books/content?id=A&zoom=3&edge=curl&source=gbs_api",
         "large":"http://books.google.com/books/content?id=A&zoom=4&edge=curl&source=gbs_api"}
        """.utf8))
        let url = try #require(GoogleBooksCover.bestImageURL(from: links))
        #expect(url.absoluteString == "https://books.google.com/books/content?id=A&zoom=4&source=gbs_api")
    }

    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])

    @Test func theLargeCoverComesFromTheVolumeAnswer() async throws {
        let client = FakeHTTPClient { url in
            url.host == "www.googleapis.com"
                ? (fixture("googlebooks-volume-garden.json"), 200)
                : (Self.jpeg, 200)
        }
        let data = await service(client).coverData(for: .googleBooks(volumeID: "xCVQ0QEACAAJ"), size: .large)
        #expect(data == Self.jpeg)
        let urls = await client.requested
        #expect(urls.count == 2)
        #expect(urls[0].path == "/books/v1/volumes/xCVQ0QEACAAJ")
        #expect(urls[1].scheme == "https" && urls[1].host == "books.google.com")
        #expect(urls[1].absoluteString.contains("id=xCVQ0QEACAAJ"))
        #expect(!urls[1].absoluteString.contains("edge=curl"))
        // The key goes only to the API call, not to the image download.
        #expect(await client.requestedHeaders == [["X-goog-api-key": Self.testKey], [:]])
    }

    @Test func theSmallCoverUsesTheContentURLWithoutTheKey() async {
        let client = FakeHTTPClient(data: Self.jpeg)
        let data = await service(client).coverData(for: .googleBooks(volumeID: "xCVQ0QEACAAJ"), size: .small)
        #expect(data == Self.jpeg)
        let urls = await client.requested
        #expect(urls.count == 1 && urls[0].absoluteString.contains("zoom=1"))
        #expect(await client.requestedHeaders == [[:]])
    }

    @Test func thePlaceholderIsNoCover() async {
        let placeholder = fixture("googlebooks-placeholder.png")
        #expect(CoverDownload.isImage(placeholder))
        #expect(GoogleBooksCover.isPlaceholder(placeholder))
        #expect(!GoogleBooksCover.isPlaceholder(Self.jpeg))
        let client = FakeHTTPClient(data: placeholder)
        #expect(await service(client).coverData(for: .googleBooks(volumeID: "pkVFjwEACAAJ"), size: .small) == nil)
    }

    @Test func coverFailuresGiveNil() async {
        let reference = CoverReference.googleBooks(volumeID: "xCVQ0QEACAAJ")
        // Other sources' references are not this service's.
        #expect(await service(FakeHTTPClient(data: Self.jpeg)).coverData(for: .dnb(isbn13: "9781804993750"), size: .small) == nil)
        // No key for the volume lookup of a large cover.
        #expect(await service(FakeHTTPClient(data: Self.jpeg), key: nil).coverData(for: reference, size: .large) == nil)
        // A volume answer without images.
        let none = FakeHTTPClient(data: Data(#"{"volumeInfo":{}}"#.utf8))
        #expect(await service(none).coverData(for: reference, size: .large) == nil)
        // HTML instead of an image.
        let html = FakeHTTPClient(data: Data("<html></html>".utf8))
        #expect(await service(html).coverData(for: reference, size: .small) == nil)
        let offline = FakeHTTPClient { _ in throw URLError(.notConnectedToInternet) }
        #expect(await service(offline).coverData(for: reference, size: .large) == nil)
    }

    // MARK: Key check

    @Test func checkKeyMapsTheAnswers() async {
        let works = FakeHTTPClient(data: fixture("googlebooks-isbn-garden.json"))
        #expect(await GoogleBooksService.checkKey("my-key", client: works) == .works)
        let url = await works.requested.first
        #expect(url.map { rawQuery($0).hasPrefix("q=isbn:9781804993750&") && rawQuery($0).contains("maxResults=1&") } == true)
        #expect(await works.requestedHeaders == [["X-goog-api-key": "my-key"]])

        let invalid = FakeHTTPClient(data: fixture("googlebooks-error-invalid-key.json"), status: 400)
        #expect(await GoogleBooksService.checkKey("bad", client: invalid) == .rejected)
        let quota = FakeHTTPClient(data: fixture("googlebooks-error-quota.json"), status: 429)
        #expect(await GoogleBooksService.checkKey("bad", client: quota) == .rejected)
        let server = FakeHTTPClient(data: Data(), status: 503)
        #expect(await GoogleBooksService.checkKey("k", client: server) == .unreachable)
        let offline = FakeHTTPClient { _ in throw URLError(.notConnectedToInternet) }
        #expect(await GoogleBooksService.checkKey("k", client: offline) == .unreachable)
    }

    // MARK: Fixtures

    /// The recorded answers must never contain a real key.
    @Test func fixturesHoldNoKey() {
        for name in [
            "googlebooks-isbn-garden.json", "googlebooks-stoner-williams.json", "googlebooks-no-match.json",
            "googlebooks-volume-garden.json", "googlebooks-error-invalid-key.json", "googlebooks-error-quota.json",
        ] {
            let text = String(decoding: fixture(name), as: UTF8.self)
            #expect(!text.isEmpty, "\(name) is empty")
            #expect(!text.contains("AIza"), "\(name) holds something that looks like a key")
        }
    }
}
