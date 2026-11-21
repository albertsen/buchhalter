import SwiftUI
import BuchhalterCore

/// "Edit Sorted As…" on an author in Authors: the one sort name of the
/// author, for all their books. Saving is one undo step.
struct EditSortNameSheet: View {
    @Environment(\.library) private var library
    @Environment(\.dismiss) private var dismiss
    var model: WindowModel
    var author: Author
    @State private var sortName: String
    @FocusState private var focused: Bool

    init(model: WindowModel, author: Author) {
        self.model = model
        self.author = author
        _sortName = State(initialValue: author.sortName)
    }

    private var canSave: Bool {
        !sortName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(author.name).font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Sorted as").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Sorted as", text: $sortName)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focused)
                    .onSubmit(save)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .sheetWidth(360, half: true)
        .onAppear { focused = true }
    }

    private func save() {
        guard canSave else { return }
        model.attempt { try library?.setSortName(sortName, for: author) }
        dismiss()
    }
}
