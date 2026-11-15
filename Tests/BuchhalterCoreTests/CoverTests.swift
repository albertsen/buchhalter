import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BuchhalterCore

struct CoverTests {
    private func makePNG(width: Int, height: Int) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func largeImagesAreDownscaledToJPEG() async throws {
        let normalized = try await CoverImage.normalize(try makePNG(width: 3000, height: 2000))
        let source = try #require(CGImageSourceCreateWithData(normalized as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        #expect(max(width, height) == 1200)
        #expect(width > height)
    }

    @Test func unreadableDataThrows() async {
        await #expect(throws: CoverImageError.self) {
            try await CoverImage.normalize(Data([1, 2, 3, 4]))
        }
    }

    @Test func paletteIsStableAndInRange() {
        let id = UUID()
        #expect(CoverPalette.index(for: id) == CoverPalette.index(for: id))
        #expect(CoverPalette.colors.count == 11)
        for _ in 0..<200 { #expect((0..<11).contains(CoverPalette.index(for: UUID()))) }
        // A fixed id gives a fixed index across launches (FNV-1a, not Hasher).
        let fixed = UUID(uuidString: "00000000-0000-0000-0000-000000000000")
        #expect(CoverPalette.index(for: fixed ?? id) == CoverPalette.index(for: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))))
    }
}
