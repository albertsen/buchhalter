import Foundation
import Testing
@testable import BuchhalterCore

struct OpenLibraryTests {
    private func service(_ data: Data, status: Int = 200) -> (OpenLibraryService, FakeHTTPClient) {
        let client = FakeHTTPClient(data: data, status: status)
        return (OpenLibraryService(client: client), client)
    }

    private func query(_ title: String, _ author: String) -> LookupQuery {
        .titleAuthor(title: title, authors: [AuthorDraft(name: author, sortName: AuthorName.guessSortName(author))])
    }

    @Test func titleAndAuthorURL() throws {
        let url = OpenLibraryService.url(for: query("Stoner", "John Williams"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.host == "openlibrary.org" && url.path == "/search.json")
        #expect(items.first { $0.name == "title" }?.value == "Stoner")
        #expect(items.first { $0.name == "author" }?.value == "John Williams")
        #expect(items.first { $0.name == "limit" }?.value == "100")
        #expect(items.first { $0.name == "fields" }?.value?.contains("editions.format") == true)
    }

    @Test func isbnURL() throws {
        let isbn = try #require({ if case .valid(let v) = ISBN.parse("9780940322776") { v } else { nil } }())
        let items = try #require(URLComponents(url: OpenLibraryService.url(for: .isbn(isbn, display: "9780940322776")), resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "isbn" }?.value == "9780940322776")
        #expect(items.first { $0.name == "title" } == nil)
    }

    @Test func stonerFixtureMapsFiveRecords() async throws {
        let (service, client) = service(fixture("openlibrary-stoner-williams.json"))
        let response = try await service.search(query("Stoner", "John Williams"))
        // The captured fixture has no `format`, so the audio edition is still there.
        #expect(response.records.count == 5)
        #expect(response.totalCount == 9)
        let urls = await client.requested
        #expect(urls.count == 1)

        let vintage = try #require(response.records.first)
        #expect(vintage.id == "openlibrary:/books/OL26424294M")
        #expect(vintage.source == .openLibrary)
        #expect(vintage.title == "Stoner")
        #expect(vintage.authors == [LookupAuthor(name: "John Williams")])
        #expect(vintage.year == 2012)
        #expect(vintage.language == "en")
        #expect(vintage.publisher == "Vintage Books")
        #expect(vintage.isbn13s == ["9780099561545"])
        // The edition's cover, not the work's (8310729).
        #expect(vintage.cover == .openLibrary(coverID: 15245132))

        #expect(response.records[1].year == 2014)
        #expect(response.records[1].language == nil)
        // No cover on the edition and none on the work either.
        #expect(response.records[3].cover == nil)
    }

    @Test func audioFormatsAreDropped() async throws {
        let json = """
        {"numFound":3,"docs":[
        {"author_name":["John Williams"],"key":"/works/1","title":"Stoner","editions":{"docs":[{"key":"/books/A","title":"Stoner","format":"audio cd"}]}},
        {"author_name":["John Williams"],"key":"/works/2","title":"Stoner","editions":{"docs":[{"key":"/books/B","title":"Stoner","format":"Paperback"}]}},
        {"author_name":["John Williams"],"key":"/works/3","title":"Stoner","editions":{"docs":[{"key":"/books/C","title":"Stoner","format":["Kindle Edition"]}]}}
        ]}
        """
        let (service, _) = service(Data(json.utf8))
        let response = try await service.search(query("Stoner", "John Williams"))
        #expect(response.records.map(\.id) == ["openlibrary:/books/B"])
    }

    @Test func pagesAndOddValuesDecode() async throws {
        let json = """
        {"numFound":1,"docs":[{"author_name":["Williams, John"],"key":"/works/1","title":"Stoner",
        "editions":{"docs":[{"key":"/books/A","title":"Stoner","subtitle":"A Novel","number_of_pages":[288],"publish_date":"September 30, 2001","publisher":"NYRB","language":["ger"]}]}}]}
        """
        let (service, _) = service(Data(json.utf8))
        let record = try #require(try await service.search(query("Stoner", "John Williams")).records.first)
        #expect(record.pages == 288)
        #expect(record.subtitle == "A Novel")
        #expect(record.year == 2001)
        #expect(record.language == "de")
        #expect(record.authors == [LookupAuthor(name: "John Williams", sortName: "Williams, John")])
    }

    @Test func renoirISBNFixtureBecomesOneRecordAfterMatching() async throws {
        let (service, _) = service(fixture("openlibrary-isbn-renoir.json"))
        let isbn = try #require({ if case .valid(let v) = ISBN.parse("9780940322776") { v } else { nil } }())
        let query = LookupQuery.isbn(isbn, display: "9780940322776")
        let response = try await service.search(query)
        #expect(response.records.count == 2)
        #expect(response.records.allSatisfy { $0.authors == [LookupAuthor(name: "Jean Renoir", sortName: "Renoir, Jean")] })
        let matches = LookupMatching.matches(response.records, for: query)
        #expect(matches.count == 1)
        #expect(matches.first?.id == "openlibrary:/books/OL3938066M")
    }

    @Test func failuresAreUnreachable() async {
        let (broken, _) = service(Data("not json".utf8))
        await #expect(throws: LookupError.unreachable(.openLibrary)) { try await broken.search(query("A", "B C")) }
        let (down, _) = service(Data(), status: 503)
        await #expect(throws: LookupError.unreachable(.openLibrary)) { try await down.search(query("A", "B C")) }
        let offline = OpenLibraryService(client: FakeHTTPClient { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: LookupError.unreachable(.openLibrary)) { try await offline.search(query("A", "B C")) }
    }

    @Test func cancellationIsNotAFailure() async {
        let cancelled = OpenLibraryService(client: FakeHTTPClient { _ in throw URLError(.cancelled) })
        await #expect(throws: CancellationError.self) { try await cancelled.search(query("A", "B C")) }
    }

    @Test func coverURLsAndChecks() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0])
        let client = FakeHTTPClient { url in url.absoluteString.contains("-L.jpg") ? (jpeg, 200) : (Data("<html>".utf8), 404) }
        let service = OpenLibraryService(client: client)
        #expect(await service.coverData(for: .openLibrary(coverID: 42), size: .large) == jpeg)
        #expect(await service.coverData(for: .openLibrary(coverID: 42), size: .small) == nil)
        let urls = await client.requested.map(\.absoluteString)
        #expect(urls.contains("https://covers.openlibrary.org/b/id/42-L.jpg?default=false"))
        #expect(urls.contains("https://covers.openlibrary.org/b/id/42-S.jpg?default=false"))
        #expect(await service.coverData(for: .dnb(isbn13: "9783935890595"), size: .large) == nil)
    }
}
