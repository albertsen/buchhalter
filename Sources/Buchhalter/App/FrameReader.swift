@preconcurrency import AVFoundation
import Vision
import os
import BuchhalterCore

/// Reads EAN-13 barcodes from the camera's frames with Vision, off the main
/// actor. It runs on the capture queue as the sample buffer delegate, looks at
/// at most 10 frames a second, drops frames while one is being read, and
/// hands the payloads and boxes over through an `AsyncStream`. It never writes
/// or uploads an image, and keeps a frame's pixel buffer only while Vision
/// reads it.
nonisolated final class FrameReader: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Frame: Sendable {
        var detections: [ScanSession.Detection]
        /// The camera image's size in pixels, which the boxes are relative to.
        var imageSize: CGSize
    }

    private struct Gate {
        var busy = false
        var lastStart: CFAbsoluteTime = 0
    }

    /// A pixel buffer is immutable while Vision reads it, and nothing else touches it.
    private struct PixelBuffer: @unchecked Sendable {
        var buffer: CVPixelBuffer
    }

    private static let minimumInterval: CFAbsoluteTime = 0.1

    /// Only frames with a barcode in them; the newest wins if the main actor is behind.
    let frames: AsyncStream<Frame>
    private let continuation: AsyncStream<Frame>.Continuation
    private let gate = OSAllocatedUnfairLock(initialState: Gate())

    override init() {
        (frames, continuation) = AsyncStream.makeStream(of: Frame.self, bufferingPolicy: .bufferingNewest(1))
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let accepted = gate.withLock { gate in
            guard !gate.busy, now - gate.lastStart >= Self.minimumInterval else { return false }
            gate.busy = true
            gate.lastStart = now
            return true
        }
        guard accepted else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            gate.withLock { $0.busy = false }
            return
        }
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let frame = PixelBuffer(buffer: pixelBuffer)
        Task.detached(priority: .userInitiated) { [self] in
            let pixelBuffer = frame.buffer
            var request = DetectBarcodesRequest()
            request.symbologies = [.ean13]
            let observations = (try? await request.perform(on: pixelBuffer)) ?? []
            let detections = observations.compactMap { observation -> ScanSession.Detection? in
                guard let payload = observation.payloadString else { return nil }
                return ScanSession.Detection(payload: payload, box: observation.boundingBox.cgRect)
            }
            gate.withLock { $0.busy = false }
            if !detections.isEmpty { continuation.yield(Frame(detections: detections, imageSize: size)) }
        }
    }
}
