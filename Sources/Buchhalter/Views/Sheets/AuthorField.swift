import SwiftUI
import BuchhalterCore

/// Author chips with an "Add author" field, and a "Sorted as" line per author.
struct AuthorField: View {
    @Environment(\.library) private var library
    @Binding var authors: [AuthorDraft]
    /// The text typed but not yet turned into a chip. The sheet commits it on save.
    @Binding var pendingName: String
    @State private var editingSortNameID: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(authors) { author in
                    Chip {
                        HStack(spacing: 4) {
                            Text(author.name)
                            Button {
                                authors.removeAll { $0.id == author.id }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(author.name)")
                        }
                    }
                }
                TextField("Add author", text: $pendingName)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 110)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            }
            ForEach($authors) { $author in
                HStack(spacing: 6) {
                    if authors.count > 1 {
                        Text(author.name).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if editingSortNameID == author.id {
                        Text("Sorted as:").font(.system(size: 12)).foregroundStyle(.secondary)
                        TextField("Sorted as", text: $author.sortName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                            .onSubmit { editingSortNameID = nil }
                        Button("Done") { editingSortNameID = nil }
                    } else {
                        Text("Sorted as: \(author.sortName)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Button("Edit") { editingSortNameID = author.id }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                    }
                }
            }
        }
    }

    /// Turns the typed name into a chip with its stored or guessed sort name.
    private func commit() {
        let name = AuthorName.normalize(pendingName)
        pendingName = ""
        guard !name.isEmpty, let library else { return }
        let draft = library.suggestedAuthor(for: name)
        guard !authors.contains(where: { AuthorName.matchKey($0.name) == AuthorName.matchKey(draft.name) }) else { return }
        authors.append(draft)
    }
}
