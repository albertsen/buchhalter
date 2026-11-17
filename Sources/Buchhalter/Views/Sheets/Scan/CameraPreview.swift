import SwiftUI
import BuchhalterCore

/// The camera picture with what is drawn over it: the white guide frame, the
/// frame on the barcode (green for an ISBN, amber for another barcode) and the
/// status. The picture is mirrored; the frame is mapped with `ScanGeometry`, so
/// it sits on the barcode where it appears in the mirrored picture, while the
/// texts read normally. The platform's layer is `CameraPreviewLayer`.
struct CameraPreview: View {
    @Environment(\.locale) private var locale
    var camera: BarcodeCamera
    var session: ScanSession
    /// The camera image's size in pixels, for `ScanGeometry`.
    var imageSize: CGSize

    /// The Mac's preview is mirrored for every camera, like FaceTime; the rear
    /// camera of an iPhone or iPad is not.
    #if os(macOS)
    private let mirrored = true
    #else
    private let mirrored = false
    #endif

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: 0x23272B)
                CameraPreviewLayer(session: camera.controller.session, mirrored: mirrored)
                frame(in: geometry.size)
                VStack {
                    Spacer()
                    status
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
    }

    // MARK: Frame

    @ViewBuilder
    private func frame(in size: CGSize) -> some View {
        if let found = foundFrame {
            let rect = ScanGeometry.overlayRect(
                normalizedBox: found.box, imageSize: imageSize, viewSize: size, mirrored: mirrored
            ).insetBy(dx: -8, dy: -8)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(found.color, lineWidth: found.width)
                .background(found.color.opacity(found.isFilled ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 10))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .animation(.easeOut(duration: 0.12), value: rect)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                .frame(width: 252, height: 110)
                .accessibilityHidden(true)
        }
    }

    private var foundFrame: (box: CGRect, color: Color, width: CGFloat, isFilled: Bool)? {
        if case .found(_, let box) = session.state { return (box, Theme.scanGreen, 3, true) }
        if let hint = session.hint { return (hint.box, Theme.scanAmber, 2, false) }
        return nil
    }

    // MARK: Status

    @ViewBuilder
    private var status: some View {
        let messages = ScanMessages(locale: locale)
        if case .found(let isbn, _) = session.state {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                Text(verbatim: messages.isbnRead(isbn))
            }
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.accent, in: Capsule())
            .accessibilityElement(children: .combine)
        } else if let hint = session.hint {
            Text(verbatim: messages.notISBN(display: hint.display))
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.scanAmberText)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Theme.scanAmberFill, in: RoundedRectangle(cornerRadius: 12))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(verbatim: messages.looking())
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.black.opacity(0.55), in: Capsule())
        }
    }
}
