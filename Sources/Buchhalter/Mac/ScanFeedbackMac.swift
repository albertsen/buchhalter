import AppKit

// Mac-only: the sound of a read and the link to the camera privacy page.

extension ScanFeedback {
    /// "Tink" when a barcode is read; System Settings → Privacy & Security → Camera.
    static let mac = ScanFeedback(
        playRead: { NSSound(named: "Tink")?.play() },
        openCameraSettings: {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
            else { return }
            NSWorkspace.shared.open(url)
        }
    )
}
