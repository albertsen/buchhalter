import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CoverImageError: Error, Sendable {
    case unreadable
}

/// Cover images are downscaled and re-encoded before they are stored, so the
/// library stays small and syncs quickly later.
public enum CoverImage {
    public static let maxPixelSize = 1200
    public static let quality = 0.85

    /// Runs off the main actor. The result is JPEG with a longest side of at
    /// most 1200 px. Throws `CoverImageError.unreadable` for anything ImageIO cannot decode.
    @concurrent
    public static func normalize(_ data: Data) async throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw CoverImageError.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CoverImageError.unreadable
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw CoverImageError.unreadable }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CoverImageError.unreadable }
        return output as Data
    }
}

extension CoverImage {
    /// A small decoded image for lists and grids. Pure ImageIO, so the views
    /// stay free of AppKit and UIKit.
    public static func thumbnail(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
