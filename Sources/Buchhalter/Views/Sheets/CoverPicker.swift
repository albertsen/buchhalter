import SwiftUI
import UniformTypeIdentifiers
import BuchhalterCore

/// The cover row of the editor: preview, a drop area (drop, paste or
/// Choose File…) and Remove Image.
struct CoverPicker: View {
    @Binding var coverData: Data?
    var title: String
    var author: String
    @State private var previewID = UUID()
    @State private var isImporting = false
    @State private var isTargeted = false
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            preview
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 6) {
                    Text("Drop an image here or paste it")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Choose File…") { isImporting = true }
                        if coverData != nil {
                            Button("Remove Image") { coverData = nil }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 62)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isTargeted || focused ? Theme.accent : Color.secondary.opacity(0.5),
                            style: StrokeStyle(lineWidth: isTargeted || focused ? 2 : 1, dash: [4, 3])
                        )
                }
                .focusable()
                .focused($focused)
                .onPasteImage { handle($0) }
                .dropDestination(for: DroppedImage.self) { items, _ in
                    guard let data = items.first?.data else { return false }
                    handle(data)
                    return true
                } isTargeted: { isTargeted = $0 }
                if failed {
                    Text("This image can't be used.")
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { handle(data) } else { failed = true }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let coverData, let image = ThumbnailCache.image(from: coverData, longestSide: 90) {
            Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else {
            GeneratedCoverView(id: previewID, title: title.isEmpty ? " " : title, author: author, size: CGSize(width: 60, height: 90))
        }
    }

    private func handle(_ data: Data) {
        Task {
            do {
                coverData = try await CoverImage.normalize(data)
                failed = false
            } catch {
                failed = true
            }
        }
    }
}
