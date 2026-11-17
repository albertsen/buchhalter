import SwiftUI
import PhotosUI
import UIKit

// iOS-only: a cover from the photo library or the camera. The image goes
// through `CoverImage.normalize` like a dropped one on the Mac.

/// Choose Photo…, Take Photo… and Remove Image under the editor's cover.
struct PhoneCoverButtons: View {
    var hasCover: Bool
    var onImage: (Data) -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotoSourceButtons(onImage: onImage)
            if hasCover {
                Button("Remove Image", role: .destructive, action: onRemove)
            }
        }
        .buttonStyle(.bordered)
    }
}

/// Choose Photo… (the photo library, no permission needed) and Take Photo…
/// (the camera, when the device has one).
struct PhotoSourceButtons: View {
    var onImage: (Data) -> Void
    @State private var item: PhotosPickerItem?
    @State private var isTakingPhoto = false

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Text("Choose Photo…")
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self) { onImage(data) }
                item = nil
            }
        }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button("Take Photo…") { isTakingPhoto = true }
                .fullScreenCover(isPresented: $isTakingPhoto) {
                    CameraCapture { data in
                        isTakingPhoto = false
                        if let data { onImage(data) }
                    }
                    .ignoresSafeArea()
                }
        }
    }
}

/// The system camera for one photo. Hands back the JPEG, or nil on Cancel.
struct CameraCapture: UIViewControllerRepresentable {
    var onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
