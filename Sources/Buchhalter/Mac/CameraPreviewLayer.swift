import SwiftUI
import AVFoundation
import AppKit

// Mac-only: the camera picture in an AppKit layer. The iOS app has its own
// `CameraPreviewLayer` over a `UIView`.

/// The live picture of a capture session, filling its view (the excess is
/// cropped). `mirrored` flips it like FaceTime: the book moves to the same
/// side as the hand. Only this layer is mirrored; the frames Vision reads are
/// not, so the barcode stays readable.
struct CameraPreviewLayer: NSViewRepresentable {
    var session: AVCaptureSession
    var mirrored: Bool

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView(session: session)
        view.mirrored = mirrored
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.mirrored = mirrored
        view.applyMirroring()
    }

    final class PreviewView: NSView {
        var mirrored = true
        private let previewLayer: AVCaptureVideoPreviewLayer
        private var observer: NSObjectProtocol?

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            installLayer()
            // The layer's connection exists once the session has a camera, which
            // happens after the view: mirror again when the picture starts.
            observer = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyMirroring() }
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        isolated deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        private func installLayer() {
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
            applyMirroring()
        }

        func applyMirroring() {
            guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
            // The value may only be set when the connection does not adjust it by itself.
            if connection.automaticallyAdjustsVideoMirroring { connection.automaticallyAdjustsVideoMirroring = false }
            if connection.isVideoMirrored != mirrored { connection.isVideoMirrored = mirrored }
        }
    }
}
