import Foundation

/// The result of trying a key before it is saved.
public enum GoogleBooksKeyCheck: Equatable, Sendable {
    case works, rejected, unreachable
}

/// Google Books API v1, with the user's own key. It builds the URL, sends the
/// key in the `X-goog-api-key` header (never in the URL, so it cannot show up
/// in an error, a fixture or a log), classifies failures, decodes and maps. It
/// does not filter matches and does not sort: Google's terms ask for results
/// as they come, and the matching is `LookupMatching`'s job like for the others.
///
/// The key is read from the `SecretStore` only when a request is about to go
/// out, because reading it can make macOS ask the user for permission.
public struct GoogleBooksService: BookLookupService {
    public let source = LookupSource.googleBooks
    /// The API's cap for `maxResults`.
    public static let maximumRecords = 40
    static let searchTimeout: TimeInterval = 20
    static let keyHeader = "X-goog-api-key"
    /// The one search that checks a key: a book Google Books has.
    static let checkISBN = "9781804993750"

    private let client: any HTTPClient
    private let keys: any SecretStore

    public init(keys: any SecretStore, client: any HTTPClient = URLSessionHTTPClient()) {
        self.keys = keys
        self.client = client
    }

    // MARK: URL

    private static let fields =
        "totalItems,items(id,volumeInfo(title,subtitle,authors,publisher,publishedDate,pageCount,language,"
        + "industryIdentifiers,imageLinks,printType,infoLink,canonicalVolumeLink),saleInfo/isEbook)"

    /// ISBN: `q=isbn:<isbn13>`. Title and author: `intitle:<word>` for each
    /// word of the title and `inauthor:<word>` for each word of the first
    /// author's surname, joined with `+`. Every value is percent-encoded
    /// (ASCII only), so a `+` in the user's text cannot split a term.
    static func url(for query: LookupQuery, maxResults: Int = maximumRecords) -> URL {
        let terms: [String]
        switch query {
        case .isbn(let isbn, _):
            terms = ["isbn:\(isbn.isbn13)"]
        case .titleAuthor(let title, let authors):
            var list = DNBService.words(in: title).map { "intitle:\(encode($0))" }
            if let first = authors.first {
                list += DNBService.words(in: DNBService.surname(of: first)).map { "inauthor:\(encode($0))" }
            }
            terms = list
        }
        return volumesURL(path: "", query: [
            "q=\(terms.joined(separator: "+"))", "printType=books", "maxResults=\(maxResults)",
            "projection=full", "fields=\(encode(fields))",
        ])
    }

    static func volumeURL(id: String) -> URL {
        volumesURL(path: "/\(encode(id))", query: ["fields=\(encode("volumeInfo/imageLinks"))"])
    }

    private static func volumesURL(path: String, query: [String]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.percentEncodedPath = "/books/v1/volumes\(path)"
        components.percentEncodedQuery = query.joined(separator: "&")
        return components.url ?? URL(fileURLWithPath: "/")
    }

    private static func encode(_ text: String) -> String {
        // ASCII only: `CharacterSet.alphanumerics` would leave "ü" unescaped.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    // MARK: Errors

    private struct ErrorAnswer: Decodable {
        struct Detail: Decodable { var reason: String? }
        struct Body: Decodable {
            var message: String?
            var errors: [Detail]?
            var details: [Detail]?
        }
        var error: Body?
    }

    /// Nil for status 200. 401, 403 and 429 are a rejected key (revoked, API
    /// not enabled for it, quota used up). 400 is one only when the answer
    /// names the key (`keyInvalid`, `API_KEY_INVALID` or "API key not valid"),
    /// so a malformed query never turns the Settings line red. Anything else
    /// is unreachable.
    static func failure(status: Int, body: Data) -> LookupError? {
        if status == 200 { return nil }
        switch status {
        case 401, 403, 429:
            return .keyRejected(.googleBooks)
        case 400:
            let error = (try? JSONDecoder().decode(ErrorAnswer.self, from: body))?.error
            let reasons = (error?.errors ?? []).compactMap(\.reason) + (error?.details ?? []).compactMap(\.reason)
            if reasons.contains("keyInvalid") || reasons.contains("API_KEY_INVALID")
                || error?.message?.contains("API key not valid") == true {
                return .keyRejected(.googleBooks)
            }
            return .unreachable(.googleBooks)
        default:
            return .unreachable(.googleBooks)
        }
    }

    /// One GET with the key. Cancellation stays cancellation; every other
    /// failure becomes a `LookupError`.
    private func fetch(_ url: URL, key: String) async throws -> Data {
        let data: Data
        let status: Int
        do {
            (data, status) = try await client.get(url, headers: [Self.keyHeader: key], timeout: Self.searchTimeout)
        } catch {
            if error.isCancellation { throw CancellationError() }
            throw LookupError.unreachable(.googleBooks)
        }
        try Task.checkCancellation()
        if let failure = Self.failure(status: status, body: data) { throw failure }
        return data
    }

    // MARK: BookLookupService

    /// - Throws: `.unreachable` when no key can be read or the service fails,
    ///   `.keyRejected` when Google refuses the key.
    @concurrent
    public func search(_ query: LookupQuery) async throws -> LookupResponse {
        guard let key = try? await keys.read(), !key.isEmpty else { throw LookupError.unreachable(.googleBooks) }
        let data = try await fetch(Self.url(for: query), key: key)
        guard let list = try? JSONDecoder().decode(GoogleBooksRecordMapper.VolumeList.self, from: data) else {
            throw LookupError.unreachable(.googleBooks)
        }
        let records = GoogleBooksRecordMapper.records(from: list)
        return LookupResponse(records: records, totalCount: list.totalItems ?? records.count)
    }

    /// Small: the content URL with `zoom=1`. Large: the content URL at zoom 3,
    /// then 2, then the single-volume answer's largest image link (often only
    /// the 128 px thumbnail). Many volumes answer the zoom levels with the
    /// placeholder, so every image must be a real picture and not Google's
    /// "image not available". Any failure gives nil.
    @concurrent
    public func coverData(for reference: CoverReference, size: CoverSize) async -> Data? {
        guard case .googleBooks(let volumeID) = reference else { return nil }
        let url: URL?
        switch size {
        case .small:
            url = GoogleBooksCover.smallURL(volumeID: volumeID)
        case .large:
            guard let key = try? await keys.read(), !key.isEmpty else { return nil }
            for zoom in GoogleBooksCover.largeZooms {
                guard let zoomed = GoogleBooksCover.contentURL(volumeID: volumeID, zoom: zoom) else { continue }
                if let image = await CoverDownload.fetch(zoomed, with: client), !GoogleBooksCover.isPlaceholder(image) {
                    return image
                }
                if Task.isCancelled { return nil }
            }
            guard let data = try? await fetch(Self.volumeURL(id: volumeID), key: key),
                  let answer = try? JSONDecoder().decode(GoogleBooksRecordMapper.VolumeImages.self, from: data),
                  let links = answer.volumeInfo?.imageLinks else { return nil }
            url = GoogleBooksCover.bestImageURL(from: links)
        }
        guard let url, let image = await CoverDownload.fetch(url, with: client),
              !GoogleBooksCover.isPlaceholder(image) else { return nil }
        return image
    }

    // MARK: Key check

    /// Tries a key with one search, before it is saved. Uses the key given,
    /// not the store's.
    @concurrent
    public static func checkKey(_ key: String, client: any HTTPClient = URLSessionHTTPClient()) async -> GoogleBooksKeyCheck {
        guard case .valid(let isbn) = ISBN.parse(checkISBN) else { return .unreachable }
        let url = url(for: .isbn(isbn, display: checkISBN), maxResults: 1)
        do {
            let (data, status) = try await client.get(url, headers: [keyHeader: key], timeout: searchTimeout)
            switch failure(status: status, body: data) {
            case nil: return .works
            case .keyRejected?: return .rejected
            default: return .unreachable
            }
        } catch {
            return .unreachable
        }
    }
}
