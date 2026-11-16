@preconcurrency import AVFoundation
import Observation
import BuchhalterCore

/// The capture session, off the main actor. `AVCaptureSession.startRunning`
/// blocks, so every call to the session happens on one serial queue. Shared
/// by the Mac and the later iOS app (AVFoundation only).
nonisolated final class CaptureController: @unchecked Sendable {
    let session = AVCaptureSession()
    let reader = FrameReader()
    private let queue = DispatchQueue(label: "local.buchhalter.camera.session")
    private let frameQueue = DispatchQueue(label: "local.buchhalter.camera.frames")
    private let output = AVCaptureVideoDataOutput()
    /// Only touched on `queue`.
    private var deviceID: String?

    init() {
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(reader, queue: frameQueue)
    }

    /// Switches the picture to another camera.
    func use(deviceID id: String) {
        queue.async { [self] in
            guard id != deviceID, let device = AVCaptureDevice(uniqueID: id),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            for old in session.inputs { session.removeInput(old) }
            if session.canAddInput(input) { session.addInput(input) }
            if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
            // 1080p reads barcodes at arm's length; the default preset can be lower.
            session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
            session.commitConfiguration()
            if (try? device.lockForConfiguration()) != nil {
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                device.unlockForConfiguration()
            }
            deviceID = id
        }
    }

    func start() {
        queue.async { [session] in
            if !session.isRunning, !session.inputs.isEmpty { session.startRunning() }
        }
    }

    /// The camera light goes off.
    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

/// The camera of the scan sheet: which cameras there are, which one is used,
/// whether the app may use it, and the barcodes it sees. It owns the session
/// while the sheet is open and stops it in every path, so the camera light
/// goes off.
@Observable
final class BarcodeCamera {
    enum State: Equatable {
        /// The system has not been asked yet, or the question is open.
        case notDetermined
        /// Camera access is off for Buchhalter.
        case denied
        /// Access is fine but no camera is connected.
        case noCamera
        case running
    }

    struct Device: Identifiable, Equatable {
        var id: String
        var name: String
    }

    private(set) var state: State = .notDetermined
    private(set) var devices: [Device] = []
    /// The camera in use; the stored choice stays as it is while that camera is away.
    private(set) var selectedID: String?

    /// Called on the main actor with each frame's barcodes and the image size.
    @ObservationIgnored var onFrame: (([ScanSession.Detection], CGSize) -> Void)?
    @ObservationIgnored let controller = CaptureController()
    @ObservationIgnored private var wantsPicture = false
    @ObservationIgnored private var isAsking = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    private static let storedKey = "scanCamera"

    // MARK: Start and stop

    /// Begins watching frames and cameras and shows the picture when allowed.
    func start() {
        wantsPicture = true
        if tasks.isEmpty { watch() }
        evaluate()
    }

    /// The picture stops (the light goes off) but the sheet stays: Add Book is open over it.
    func pause() {
        wantsPicture = false
        controller.stop()
    }

    /// Everything stops, for good: the sheet is closing. The callback goes too,
    /// because it captures the sheet that owns this object.
    func stop() {
        pause()
        onFrame = nil
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func watch() {
        tasks.append(Task { [weak self] in
            guard let frames = self?.controller.reader.frames else { return }
            for await frame in frames {
                guard let self else { return }
                self.onFrame?(frame.detections, frame.imageSize)
            }
        })
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            tasks.append(Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    self?.evaluate()
                }
            })
        }
    }

    // MARK: Authorization and cameras

    /// Reads what is allowed and connected and brings the session in line. Cheap
    /// enough to call again when the app becomes active or on a timer.
    func evaluate() {
        refreshDevices()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            state = .notDetermined
            guard !isAsking else { return }
            isAsking = true
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                isAsking = false
                evaluate()
            }
        case .denied, .restricted:
            state = .denied
            controller.stop()
        case .authorized:
            guard let selectedID else {
                state = .noCamera
                controller.stop()
                return
            }
            state = .running
            controller.use(deviceID: selectedID)
            if wantsPicture { controller.start() }
        @unknown default:
            state = .denied
        }
    }

    private func refreshDevices() {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .continuityCamera, .external]
        types.removeAll { $0 == .continuityCamera && !Self.allowsContinuityCamera }
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
            .devices
        devices = found.map { Device(id: $0.uniqueID, name: $0.localizedName) }
        let candidates = found.map { device in
            CameraChoice.Candidate(
                id: device.uniqueID,
                kind: device.isContinuityCamera ? .continuity : device.deviceType == .external ? .external : .builtIn
            )
        }
        selectedID = CameraChoice.pick(
            from: candidates, stored: UserDefaults.standard.string(forKey: Self.storedKey),
            systemPreferred: AVCaptureDevice.systemPreferredCamera?.uniqueID
        )
    }

    /// The user picked a camera: kept on this Mac, and the picture switches at once.
    func select(_ id: String) {
        UserDefaults.standard.set(id, forKey: Self.storedKey)
        evaluate()
    }

    /// Info.plist opts in with `NSCameraUseContinuityCameraDeviceType`; without it
    /// the iPhone shows up as a plain wide-angle camera, so nothing is lost.
    private static var allowsContinuityCamera: Bool { true }
}
