import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox
import BuchhalterCore

// iOS-only counterparts of the Mac-only helpers the shared views call. Each
// has the name and signature of its Mac twin in Sources/Buchhalter/Mac.

// MARK: Subtitle

extension View {
    /// The Mac's navigation subtitle (the book count under the list name). iOS
    /// has no navigation subtitle, so the count sits above the list.
    func librarySubtitle(_ text: String) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Text(verbatim: text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
                .background(.bar.opacity(0))
        }
    }
}

// MARK: Find Cover alerts

/// Find Cover's and Find Synopsis's alerts; "Open Settings…" opens the Settings sheet.
struct FindCoverAlertModifier: ViewModifier {
    @Environment(PhoneUI.self) private var phone
    @Environment(\.locale) private var locale
    var model: WindowModel

    func body(content: Content) -> some View {
        content.alert(
            title, isPresented: Binding(get: { model.findAlert != nil }, set: { if !$0 { model.findAlert = nil } }),
            presenting: model.findAlert
        ) { alert in
            if alert.suggestsGoogleBooks {
                Button("Open Settings…") { phone.settings = .bookLookup }
            }
            Button("OK", role: .cancel) {}
        } message: { alert in
            switch alert {
            case .noCover(let suggestsGoogleBooks):
                Text(verbatim: LookupMessages(locale: locale).noCoverMessage(suggestingGoogleBooks: suggestsGoogleBooks))
            case .noSynopsis(let suggestsGoogleBooks):
                Text(verbatim: LookupMessages(locale: locale).noSynopsisMessage(suggestingGoogleBooks: suggestsGoogleBooks))
            case .noSourceReached:
                Text("Check the internet connection.")
            }
        }
    }

    private var title: LocalizedStringKey {
        switch model.findAlert {
        case .noSourceReached: "Can't reach any book source"
        case .noSynopsis: "No synopsis found"
        case .noCover, nil: "No cover found"
        }
    }
}

// MARK: Scan feedback

extension ScanFeedback {
    /// A haptic tap and the system's short sound (silent with the ringer off);
    /// Buchhalter's page in the Settings app for camera access.
    static let phone = ScanFeedback(
        playRead: {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(1057)
        },
        openCameraSettings: { PhoneSystemSettings.openAppSettings() }
    )
}

// MARK: Camera picture

/// The live picture of a capture session in a `UIView`, filling it (the
/// excess cropped). The rear camera is never mirrored; `mirrored` exists for
/// the shared `CameraPreview`, which passes false on iOS.
struct CameraPreviewLayer: UIViewRepresentable {
    var session: AVCaptureSession
    var mirrored: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session { view.previewLayer.session = session }
    }

    final class PreviewView: UIView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
            let angle = CameraRotation.angle(for: window?.windowScene)
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }
}

/// The rotation of the rear camera's picture for the screen's orientation:
/// 90° in portrait. The preview and the frames Vision reads use the same angle,
/// so the barcode's box lands where the barcode shows.
enum CameraRotation {
    static func angle(for scene: UIWindowScene?) -> CGFloat {
        switch scene?.effectiveGeometry.interfaceOrientation ?? .portrait {
        case .portraitUpsideDown: 270
        case .landscapeLeft: 180
        case .landscapeRight: 0
        default: 90
        }
    }
}
