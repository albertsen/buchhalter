import SwiftUI

/// What the platform adds to a read: a sound on the Mac, a haptic on iOS, and
/// the way to the camera privacy page. The shared view stays free of AppKit;
/// each app sets it (`.mac`, `.phone`).
struct ScanFeedback {
    var playRead: () -> Void = {}
    var openCameraSettings: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var scanFeedback = ScanFeedback()
}
