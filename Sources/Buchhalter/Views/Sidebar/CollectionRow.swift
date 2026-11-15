import SwiftUI
import BuchhalterCore

/// A collection in the sidebar: name and count, an inline rename field, a
/// drop target for books, and a context menu.
struct CollectionRow: View {
    @Environment(\.library) private var library
    var model: WindowModel
    var collection: Collection
    var count: Int
    @State private var name = ""
    @State private var error: String?
    @State private var isDropTarget = false

    var body: some View {
        Group {
            if model.renamingCollectionID == collection.id {
                CollectionNameField(
                    text: $name, error: error,
                    onSubmit: rename,
                    onCancel: { model.renamingCollectionID = nil }
                )
                .onAppear { name = collection.name; error = nil }
            } else {
                HStack {
                    Label(collection.name, systemImage: "folder")
                    Spacer()
                    Text(count, format: .number)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 1)
                .background(isDropTarget ? Theme.accent.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .contextMenu {
            Button("Rename") { model.renamingCollectionID = collection.id }
            Button("Delete Collection…", role: .destructive) { model.pendingDeleteCollectionID = collection.id }
        }
        .dropDestination(for: BookDragItem.self) { items, _ in
            guard let library else { return false }
            model.attempt {
                for item in items {
                    if let book = library.book(withID: item.id) { try library.add(book, to: collection) }
                }
            }
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    private func rename() {
        guard let library else { return }
        do {
            try library.renameCollection(collection, to: name)
            model.renamingCollectionID = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A text field with an error line. Return submits, Esc cancels.
struct CollectionNameField: View {
    @Binding var text: String
    var error: String?
    var onSubmit: () -> Void
    var onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onCancel)
                .accessibilityLabel("Collection name")
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.error)
            }
        }
        .onAppear { focused = true }
    }
}
