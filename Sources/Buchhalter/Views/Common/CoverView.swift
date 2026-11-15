import SwiftUI
import BuchhalterCore

/// A book's cover: its image, or a generated one (a solid colour from the
/// book's id, with title and author in the serif).
struct CoverView: View {
    var book: Book
    /// Longest side in points, for decoding a right-sized thumbnail.
    var size: CGSize

    var body: some View {
        let radius: CGFloat = size.width > 100 ? 4 : 3
        Group {
            if let image = ThumbnailCache.image(for: book, longestSide: max(size.width, size.height)) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                GeneratedCoverView(
                    id: book.id, title: book.title,
                    author: book.orderedAuthors.map(\.name).joined(separator: ", "), size: size
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .shadow(color: .black.opacity(size.width > 100 ? 0.18 : 0), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}

struct GeneratedCoverView: View {
    var id: UUID
    var title: String
    var author: String
    var size: CGSize

    var body: some View {
        let scale = size.width / 120
        ZStack(alignment: .bottomLeading) {
            Theme.coverColor(for: id)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Theme.serif(max(7, 15 * scale)))
                    .lineLimit(size.width > 100 ? 5 : 3)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if size.width > 60, !author.isEmpty {
                    Text(author)
                        .font(Theme.serif(max(7, 10 * scale), weight: .regular))
                        .opacity(0.85)
                        .lineLimit(2)
                }
            }
            .foregroundStyle(.white)
            .padding(max(4, 12 * scale))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Decoded thumbnails, so scrolling a list does not decode the image again.
@MainActor
enum ThumbnailCache {
    private final class Box { let image: CGImage; init(_ image: CGImage) { self.image = image } }
    private static let cache = NSCache<NSString, Box>()

    static func image(for book: Book, longestSide: CGFloat) -> CGImage? {
        guard let data = book.coverImage else { return nil }
        let pixels = Int(longestSide * 2)
        let key = "\(book.id.uuidString)-\(pixels)-\(data.count)" as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        guard let image = CoverImage.thumbnail(from: data, maxPixelSize: pixels) else { return nil }
        cache.setObject(Box(image), forKey: key)
        return image
    }

    /// For the editor, where the image is not stored yet.
    static func image(from data: Data, longestSide: CGFloat) -> CGImage? {
        CoverImage.thumbnail(from: data, maxPixelSize: Int(longestSide * 2))
    }
}
