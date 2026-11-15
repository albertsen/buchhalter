import SwiftUI
import UniformTypeIdentifiers

// Mac-only: `onPasteCommand` does not exist on iOS.

extension View {
    /// Handles ⌘V on the focused view when the pasteboard holds an image or an image file.
    func onPasteImage(perform action: @escaping @MainActor @Sendable (Data) -> Void) -> some View {
        onPasteCommand(of: [UTType.image, UTType.fileURL]) { providers in
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        guard let data else { return }
                        Task { @MainActor in action(data) }
                    }
                    return
                } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url, let data = try? Data(contentsOf: url) else { return }
                        Task { @MainActor in action(data) }
                    }
                    return
                }
            }
        }
    }
}
