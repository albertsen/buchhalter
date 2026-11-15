import Foundation

/// The Deutsche Nationalbibliothek's SRU interface (MARC 21 over XML).
/// Anonymous, no key; the metadata is CC0. It builds the URL, fetches, parses
/// and maps, and drops records that are not printed books. It does not filter
/// matches (`LookupMatching`) and does not sort.
public struct DNBService: BookLookupService {
    public let source = LookupSource.dnb
    /// The server's cap for `maximumRecords` is 100; 500 fails.
    public static let maximumRecords = 100
    static let searchTimeout: TimeInterval = 20

    private let client: any HTTPClient

    public init(client: any HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    // MARK: URL

    /// Title and author: `tit=<word> and tit=<word> and per=<surname> and mat=books`.
    /// ISBN: `num=<isbn13>`. The query value is percent-encoded with `=` and
    /// `+` escaped, because the query itself contains them.
    static func url(for query: LookupQuery) -> URL {
        let cql: String
        let limit: Int
        switch query {
        case .isbn(let isbn, _):
            cql = "num=\(isbn.isbn13)"
            limit = 10
        case .titleAuthor(let title, let authors):
            var clauses = words(in: title).map { "tit=\($0)" }
            if let first = authors.first {
                clauses += words(in: surname(of: first)).map { "per=\($0)" }
            }
            clauses.append("mat=books")
            cql = clauses.joined(separator: " and ")
            limit = maximumRecords
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "services.dnb.de"
        components.path = "/sru/dnb"
        components.percentEncodedQuery = [
            "version=1.1", "operation=searchRetrieve", "recordSchema=MARC21-xml",
            "maximumRecords=\(limit)", "query=\(encode(cql))",
        ].joined(separator: "&")
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// The part of the sort name before the comma, or the last word of the name.
    static func surname(of author: AuthorDraft) -> String {
        if let comma = author.sortName.firstIndex(of: ",") {
            let surname = author.sortName[..<comma].trimmingCharacters(in: .whitespaces)
            if !surname.isEmpty { return surname }
        }
        return AuthorName.normalize(author.name).split(separator: " ").last.map(String.init) ?? author.name
    }

    /// Words split on whitespace, with CQL's special characters removed and
    /// the operators dropped ("Pride and Prejudice" must not break the query).
    static func words(in text: String) -> [String] {
        let special = CharacterSet(charactersIn: "\"()=<>/*\\?:;,!")
        let operators: Set<String> = ["and", "or", "not", "prox"]
        return text.components(separatedBy: special).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).map(String.init)
            .filter { !operators.contains($0.lowercased()) }
    }

    private static func encode(_ text: String) -> String {
        // ASCII only: `CharacterSet.alphanumerics` would leave "ü" unescaped.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
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
            throw LookupError.unreachable(.dnb)
        }
        try Task.checkCancellation()
        guard status == 200, let parsed = try? MARCXMLParser.parse(data), !parsed.hasDiagnostic else {
            throw LookupError.unreachable(.dnb)
        }
        let records = parsed.records.compactMap(DNBRecordMapper.record(from:))
        return LookupResponse(records: records, totalCount: parsed.numberOfRecords)
    }

    /// The MVB cover service behind the DNB portal is undocumented, so every
    /// failure means "no cover".
    @concurrent
    public func coverData(for reference: CoverReference, size: CoverSize) async -> Data? {
        guard case .dnb(let isbn13) = reference else { return nil }
        let suffix = size == .small ? "&size=s" : "&size=l"
        guard let url = URL(string: "https://portal.dnb.de/opac/mvb/cover?isbn=\(isbn13)\(suffix)") else { return nil }
        return await CoverDownload.fetch(url, with: client)
    }
}
