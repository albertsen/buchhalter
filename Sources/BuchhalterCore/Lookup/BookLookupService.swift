import Foundation

/// One book data service. Implementations build the request, parse the
/// answer and map it to `LookupRecord`s; they do not filter matches or sort.
public protocol BookLookupService: Sendable {
    var source: LookupSource { get }
    /// Throws `LookupError.unreachable` for any failure other than cancellation,
    /// or `.keyRejected` when the service refuses the user's API key.
    func search(_ query: LookupQuery) async throws -> LookupResponse
    /// The cover's bytes, or nil on any failure: no cover, a timeout, an HTML
    /// error page. A missing cover is normal and shows no message.
    func coverData(for reference: CoverReference, size: CoverSize) async -> Data?
}

/// The checks every cover download shares.
enum CoverDownload {
    static let timeout: TimeInterval = 15

    static func fetch(_ url: URL, with client: any HTTPClient) async -> Data? {
        guard let (data, status) = try? await client.get(url, timeout: timeout), status == 200,
              isImage(data) else { return nil }
        return data
    }

    /// Both services answer a missing cover with an HTML page or an empty
    /// body, so the bytes must start with a JPEG or PNG signature.
    static func isImage(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        return bytes == [0x89, 0x50, 0x4E, 0x47]
    }
}
