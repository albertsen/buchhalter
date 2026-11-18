import CoreGraphics
import Foundation
import ImageIO

/// The Google Books answer shapes and their mapping to `LookupRecord`s. Only
/// the fields the app uses are decoded, and the service asks for exactly
/// those through the `fields` parameter.
enum GoogleBooksRecordMapper {
    // MARK: Decoding

    struct VolumeList: Decodable {
        var totalItems: Int?
        var items: [Volume]?
    }

    struct Volume: Decodable {
        var id: String?
        var volumeInfo: VolumeInfo?
        var saleInfo: SaleInfo?
    }

    struct SaleInfo: Decodable {
        var isEbook: Bool?
    }

    struct VolumeInfo: Decodable {
        var title: String?
        var subtitle: String?
        var authors: [String]?
        var publisher: String?
        var publishedDate: String?
        var pageCount: Int?
        var language: String?
        var industryIdentifiers: [Identifier]?
        var imageLinks: ImageLinks?
        var printType: String?
        var infoLink: String?
        var canonicalVolumeLink: String?
        /// HTML with `b`, `i`, `br` and `p`.
        var description: String?
    }

    struct Identifier: Decodable {
        var type: String?
        var identifier: String?
    }

    struct ImageLinks: Decodable {
        var smallThumbnail: String?
        var thumbnail: String?
        var small: String?
        var medium: String?
        var large: String?
        var extraLarge: String?
    }

    /// The single-volume answer asked with `fields=volumeInfo/imageLinks`.
    struct VolumeImages: Decodable {
        var volumeInfo: VolumeInfo?
    }

    // MARK: Mapping

    /// The records of a list answer: printed books only, in Google's order.
    static func records(from list: VolumeList) -> [LookupRecord] {
        (list.items ?? []).compactMap(record(from:))
    }

    /// Nil for a volume that is not a printed book (a magazine, an e-book),
    /// has no title, or has no id. Google has no audiobook flag, so
    /// audiobooks come out only through `printType`.
    static func record(from volume: Volume) -> LookupRecord? {
        guard let info = volume.volumeInfo, let id = volume.id, !id.isEmpty,
              info.printType == nil || info.printType == "BOOK",
              volume.saleInfo?.isEbook != true else { return nil }
        let title = AuthorName.normalize(info.title ?? "")
        guard !title.isEmpty else { return nil }
        var seen = Set<String>()
        let isbn13s = (info.industryIdentifiers ?? [])
            .filter { $0.type == "ISBN_13" || $0.type == "ISBN_10" }
            .compactMap { entry -> String? in
                guard let raw = entry.identifier, case .valid(let isbn) = ISBN.parse(raw) else { return nil }
                return isbn.isbn13
            }
            .filter { seen.insert($0).inserted }
        return LookupRecord(
            id: "googlebooks:\(id)", source: .googleBooks, title: title,
            subtitle: trimmedOrNil(info.subtitle),
            authors: (info.authors ?? []).map(author(from:)).filter { !$0.name.isEmpty },
            year: info.publishedDate.flatMap(LookupMatching.year(in:)),
            pages: info.pageCount.flatMap { (1...99_999).contains($0) ? $0 : nil },
            language: info.language.flatMap(language(from:)),
            publisher: trimmedOrNil(info.publisher),
            isbn13s: isbn13s, isbnDisplay: isbn13s.first,
            cover: info.imageLinks?.thumbnail == nil ? nil : .googleBooks(volumeID: id),
            webPage: webPage(info),
            synopsis: info.description.flatMap(SynopsisText.plain(fromHTML:)).map { .text($0) }
        )
    }

    /// Google gives "Nick Newman", sometimes with a role ("John Williams
    /// (author.)"), which is cut off.
    private static func author(from name: String) -> LookupAuthor {
        var text = name
        if text.hasSuffix(")"), let open = text.lastIndex(of: "(") { text = String(text[..<open]) }
        return LookupMatching.headingToName(text)
    }

    /// A two-letter code, lowercased; "pt-BR" gives "pt". Anything else is nil.
    private static func language(from code: String) -> String? {
        let primary = code.lowercased().split(separator: "-").first.map(String.init) ?? ""
        return primary.count == 2 && primary.allSatisfy({ $0.isASCII && $0.isLetter }) ? primary : nil
    }

    /// The canonical link, else the info link, as https.
    private static func webPage(_ info: VolumeInfo) -> URL? {
        for text in [info.canonicalVolumeLink, info.infoLink] {
            if let text, let url = GoogleBooksCover.secure(text) { return url }
        }
        return nil
    }
}

/// Google's cover links: https, no page curl, the largest size on offer, and
/// the "image not available" picture recognized.
enum GoogleBooksCover {
    /// The content URL of a volume's cover. `zoom=1` is a small image.
    static func smallURL(volumeID: String) -> URL? { contentURL(volumeID: volumeID, zoom: 1) }

    /// The zoom levels tried for a large cover, largest first: 3 is about
    /// 575 px wide, 2 about 300 px. Many volumes answer them with the
    /// placeholder, so each result is checked; the single-volume answer's
    /// links (often only the 128 px thumbnail) are the fallback.
    static let largeZooms = [3, 2]

    /// A volume's cover at a zoom level. Needs no key.
    static func contentURL(volumeID: String, zoom: Int) -> URL? {
        var components = URLComponents(string: "https://books.google.com/books/content")
        components?.queryItems = [
            URLQueryItem(name: "id", value: volumeID), URLQueryItem(name: "printsec", value: "frontcover"),
            URLQueryItem(name: "img", value: "1"), URLQueryItem(name: "zoom", value: String(zoom)),
            URLQueryItem(name: "source", value: "gbs_api"),
        ]
        return components?.url
    }

    /// The largest link of a single-volume answer, as https without `edge=curl`.
    static func bestImageURL(from links: GoogleBooksRecordMapper.ImageLinks) -> URL? {
        let candidates = [links.extraLarge, links.large, links.medium, links.small, links.thumbnail, links.smallThumbnail]
        for text in candidates {
            if let text, let url = secure(text, removingCurl: true) { return url }
        }
        return nil
    }

    /// Google answers with `http`, which App Transport Security refuses.
    static func secure(_ text: String, removingCurl: Bool = false) -> URL? {
        guard var components = URLComponents(string: text) else { return nil }
        if components.scheme == "http" { components.scheme = "https" }
        guard components.scheme == "https" else { return nil }
        if removingCurl { components.queryItems = components.queryItems?.filter { $0.name != "edge" } }
        return components.url
    }

    // MARK: Placeholder

    /// The "image not available" pictures Google serves for a volume without
    /// a cover, one per size: 128 x 170 (1269 bytes, zoom 1), 300 x 391
    /// (15567 bytes, zoom 2) and 575 x 750 (9103 bytes, zoom 3), recorded in
    /// the fixtures `googlebooks-placeholder*.png`. Matching size and byte
    /// count recognize them; a real cover has neither.
    static let placeholders: [(width: Int, height: Int, bytes: Int)] = [
        (128, 170, 1269), (300, 391, 15567), (575, 750, 9103),
    ]

    static func isPlaceholder(_ data: Data) -> Bool {
        guard placeholders.contains(where: { $0.bytes == data.count }),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return placeholders.contains { $0.width == width && $0.height == height && $0.bytes == data.count }
    }
}
