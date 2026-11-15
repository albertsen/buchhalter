import Foundation

/// Open Library's search API: free, no key, mostly English books. By default it is the
/// second source, after the Deutsche Nationalbibliothek. Each work
/// comes with its best-matching edition; that edition is the record.
public struct OpenLibraryService: BookLookupService {
    public let source = LookupSource.openLibrary
    public static let maximumRecords = 100
    static let searchTimeout: TimeInterval = 20

    private let client: any HTTPClient

    public init(client: any HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    // MARK: URL

    private static let fields = [
        "key", "title", "subtitle", "author_name", "cover_i", "editions", "editions.key", "editions.title",
        "editions.subtitle", "editions.cover_i", "editions.language", "editions.publisher",
        "editions.publish_date", "editions.isbn", "editions.number_of_pages", "editions.format",
    ].joined(separator: ",")

    static func url(for query: LookupQuery) -> URL {
        var items: [URLQueryItem]
        switch query {
        case .isbn(let isbn, _):
            items = [URLQueryItem(name: "isbn", value: isbn.isbn13)]
        case .titleAuthor(let title, let authors):
            items = [URLQueryItem(name: "title", value: AuthorName.normalize(title))]
            if let first = authors.first { items.append(URLQueryItem(name: "author", value: AuthorName.normalize(first.name))) }
        }
        items.append(URLQueryItem(name: "fields", value: fields))
        items.append(URLQueryItem(name: "limit", value: String(maximumRecords)))
        var components = URLComponents(string: "https://openlibrary.org/search.json") ?? URLComponents()
        components.queryItems = items
        return components.url ?? URL(fileURLWithPath: "/")
    }

    // MARK: Decoding

    private struct SearchResponse: Decodable {
        var numFound: Int?
        var docs: [Work]?
    }

    private struct Work: Decodable {
        var key: String?
        var title: String?
        var subtitle: String?
        var author_name: [String]?
        var cover_i: Int?
        var editions: Editions?
    }

    private struct Editions: Decodable {
        var docs: [Edition]?
    }

    /// Open Library returns most fields as arrays, but a few as a single
    /// value; reading both keeps one odd record from failing the whole answer.
    private struct Edition: Decodable {
        var key: String?
        var title: String?
        var subtitle: String?
        var cover_i: Int?
        var language: [String] = []
        var publisher: [String] = []
        var publish_date: [String] = []
        var isbn: [String] = []
        var number_of_pages: Int?
        var format: [String] = []

        enum CodingKeys: String, CodingKey {
            case key, title, subtitle, cover_i, language, publisher, publish_date, isbn, number_of_pages, format
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func strings(_ key: CodingKeys) -> [String] {
                if let list = try? c.decodeIfPresent([String].self, forKey: key) { return list }
                if let single = try? c.decodeIfPresent(String.self, forKey: key) { return [single] }
                return []
            }
            key = try? c.decodeIfPresent(String.self, forKey: .key)
            title = try? c.decodeIfPresent(String.self, forKey: .title)
            subtitle = try? c.decodeIfPresent(String.self, forKey: .subtitle)
            cover_i = try? c.decodeIfPresent(Int.self, forKey: .cover_i)
            language = strings(.language)
            publisher = strings(.publisher)
            publish_date = strings(.publish_date)
            isbn = strings(.isbn)
            format = strings(.format)
            if let pages = try? c.decodeIfPresent(Int.self, forKey: .number_of_pages) {
                number_of_pages = pages
            } else if let pages = try? c.decodeIfPresent([Int].self, forKey: .number_of_pages) {
                number_of_pages = pages.first
            }
        }
    }

    // MARK: Mapping

    private static let nonPrintFormats = ["audio", "cd", "mp3", "ebook", "e-book", "kindle"]

    /// Nil for an edition whose format names something other than print. An
    /// edition without a format is kept.
    private static func record(from work: Work) -> LookupRecord? {
        let edition = work.editions?.docs?.first
        if let edition {
            let formats = edition.format.map { TextFolding.fold($0) }
            if formats.contains(where: { format in nonPrintFormats.contains { format.contains($0) } }) { return nil }
        }
        let title = AuthorName.normalize(edition?.title ?? work.title ?? "")
        guard !title.isEmpty, let key = edition?.key ?? work.key else { return nil }
        let isbn13s = (edition?.isbn ?? []).compactMap { raw -> String? in
            if case .valid(let isbn) = ISBN.parse(raw) { isbn.isbn13 } else { nil }
        }
        var seen = Set<String>()
        let unique = isbn13s.filter { seen.insert($0).inserted }
        let subtitle = trimmedOrNil(edition?.subtitle ?? work.subtitle)
        return LookupRecord(
            id: "openlibrary:\(key)", source: .openLibrary, title: title, subtitle: subtitle,
            authors: (work.author_name ?? []).map(LookupMatching.headingToName).filter { !$0.name.isEmpty },
            year: edition?.publish_date.first.flatMap(LookupMatching.year(in:)),
            pages: edition?.number_of_pages.flatMap { (1...99_999).contains($0) ? $0 : nil },
            language: edition?.language.first.flatMap(BibliographicLanguage.alpha2),
            publisher: trimmedOrNil(edition?.publisher.first),
            isbn13s: unique, isbnDisplay: unique.first,
            // The edition's own cover. The work's cover belongs to another edition.
            cover: edition?.cover_i.map { .openLibrary(coverID: $0) },
            workCover: work.cover_i.map { .openLibrary(coverID: $0) }
        )
    }

    // MARK: BookLookupService

    @concurrent
    public func search(_ query: LookupQuery) async throws -> LookupResponse {
        let data: Data
        let status: Int
        do {
            (data, status) = try await client.get(Self.url(for: query), timeout: Self.searchTimeout)
        } catch {
            if error.isCancellation { throw CancellationError() }
            throw LookupError.unreachable(.openLibrary)
        }
        try Task.checkCancellation()
        guard status == 200, let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
            throw LookupError.unreachable(.openLibrary)
        }
        let records = (decoded.docs ?? []).compactMap(Self.record(from:))
        return LookupResponse(records: records, totalCount: decoded.numFound ?? records.count)
    }

    @concurrent
    public func coverData(for reference: CoverReference, size: CoverSize) async -> Data? {
        guard case .openLibrary(let id) = reference else { return nil }
        let letter = size == .small ? "S" : "L"
        guard let url = URL(string: "https://covers.openlibrary.org/b/id/\(id)-\(letter).jpg?default=false") else { return nil }
        return await CoverDownload.fetch(url, with: client)
    }
}
