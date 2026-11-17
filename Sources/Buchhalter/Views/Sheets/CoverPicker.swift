import SwiftUI
import UniformTypeIdentifiers
import BuchhalterCore

/// The cover row of the editor: preview, a drop area (drop, paste or
/// Choose File…) and Remove Image on the Mac; Choose Photo…, Take Photo… and
/// Remove Image on iOS.
struct CoverPicker: View {
    @Binding var coverData: Data?
    var title: String
    var author: String
    /// True while the cover is the one Complete filled in: a green outline.
    var highlighted = false
    /// "Use DNB cover", offered when the book has a cover of its own.
    var offer: (label: String, action: () -> Void)?
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
                .overlay {
                    // A 2 pt outline with a 2 pt gap, like the design.
                    if highlighted {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.filledBorder, lineWidth: 2).padding(-4)
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                #if os(iOS)
                PhoneCoverButtons(hasCover: coverData != nil, onImage: { handle($0) }, onRemove: { coverData = nil })
                #else
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
                #endif
                if let offer {
                    Button(action: offer.action) { Text(verbatim: offer.label) }
                        .linkButtonStyle()
                        .font(.system(size: 11))
                }
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
