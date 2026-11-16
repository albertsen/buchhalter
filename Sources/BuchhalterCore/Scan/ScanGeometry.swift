import Foundation

/// Maps a barcode's box from the camera image to the preview, in points.
/// Vision reports a normalized box with its origin at the bottom left, in the
/// image's own orientation. The preview fills its view (aspect fill, the
/// excess cropped) and is mirrored like FaceTime for every camera, so the
/// overlay flips y, scales like the picture and mirrors x.
public enum ScanGeometry {
    public static func overlayRect(
        normalizedBox box: CGRect, imageSize: CGSize, viewSize: CGSize, mirrored: Bool
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (viewSize.width - imageSize.width * scale) / 2
        let offsetY = (viewSize.height - imageSize.height * scale) / 2
        let width = box.width * imageSize.width * scale
        let height = box.height * imageSize.height * scale
        var x = box.minX * imageSize.width * scale + offsetX
        let y = (1 - box.maxY) * imageSize.height * scale + offsetY
        if mirrored { x = viewSize.width - x - width }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
