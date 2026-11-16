import CoreGraphics
import Testing
@testable import BuchhalterCore

struct ScanGeometryTests {
    private func expectEqual(_ a: CGRect, _ b: CGRect, _ message: String = "", line: UInt = #line) {
        let close = abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01
            && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
        #expect(close, "\(a) is not \(b) \(message)")
    }

    @Test func aCenteredBoxStaysCentered() {
        let box = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        for mirrored in [false, true] {
            let rect = ScanGeometry.overlayRect(
                normalizedBox: box, imageSize: CGSize(width: 1920, height: 1080),
                viewSize: CGSize(width: 512, height: 330), mirrored: mirrored
            )
            #expect(abs(rect.midX - 256) < 0.01)
            #expect(abs(rect.midY - 165) < 0.01)
        }
    }

    @Test func aBoxAtTheLeftLandsAtTheRightWhenMirrored() {
        // Same aspect ratio as the view, so nothing is cropped.
        let box = CGRect(x: 0, y: 0.4, width: 0.25, height: 0.2)
        let image = CGSize(width: 400, height: 200)
        let view = CGSize(width: 400, height: 200)
        let plain = ScanGeometry.overlayRect(normalizedBox: box, imageSize: image, viewSize: view, mirrored: false)
        let mirrored = ScanGeometry.overlayRect(normalizedBox: box, imageSize: image, viewSize: view, mirrored: true)
        expectEqual(plain, CGRect(x: 0, y: 80, width: 100, height: 40))
        expectEqual(mirrored, CGRect(x: 300, y: 80, width: 100, height: 40))
    }

    @Test func theYAxisIsFlipped() {
        // Vision's origin is bottom left: a box at the bottom of the image is at the bottom of the view.
        let box = CGRect(x: 0.5, y: 0, width: 0.25, height: 0.25)
        let rect = ScanGeometry.overlayRect(
            normalizedBox: box, imageSize: CGSize(width: 400, height: 200),
            viewSize: CGSize(width: 400, height: 200), mirrored: false
        )
        expectEqual(rect, CGRect(x: 200, y: 150, width: 100, height: 50))
    }

    @Test func aspectFillCropsTheSides() {
        // 1920 x 1080 in 512 x 330: scale 330/1080, 586.67 points wide, 37.33 cropped each side.
        let scale = 330.0 / 1080.0
        let box = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let rect = ScanGeometry.overlayRect(
            normalizedBox: box, imageSize: CGSize(width: 1920, height: 1080),
            viewSize: CGSize(width: 512, height: 330), mirrored: false
        )
        expectEqual(rect, CGRect(
            x: 0.25 * 1920 * scale - (1920 * scale - 512) / 2, y: 0.25 * 1080 * scale,
            width: 0.5 * 1920 * scale, height: 0.25 * 1080 * scale
        ))
    }

    @Test func aDegenerateSizeGivesAnEmptyRect() {
        let rect = ScanGeometry.overlayRect(
            normalizedBox: CGRect(x: 0, y: 0, width: 1, height: 1), imageSize: .zero,
            viewSize: CGSize(width: 100, height: 100), mirrored: false
        )
        #expect(rect == .zero)
    }
}
