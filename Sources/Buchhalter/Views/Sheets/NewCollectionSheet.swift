import SwiftUI
import BuchhalterCore

/// A name sheet for "New Collection…" in the book menu: creates the
/// collection and adds the book in one undo step.
struct NewCollectionSheet: View {
    @Environment(\.library) private var library
    @Environment(\.dismiss) private var dismiss
    var model: WindowModel
    var book: Book?
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Collection").font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: $name)
                    .focused($focused)
                    .onSubmit(create)
                    .accessibilityLabel("Collection name")
                if let error {
                    Text(error).font(.caption).foregroundStyle(Theme.error)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    private func create() {
        guard let library else { return }
        do {
            if let book {
                try library.createCollection(named: name, adding: book)
            } else {
                try library.createCollection(named: name)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
