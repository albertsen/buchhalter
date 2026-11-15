import SwiftUI
import BuchhalterCore

/// The Library lists and the user's collections, with counts.
struct SidebarView: View {
    @Environment(\.library) private var library
    var model: WindowModel
    var collections: [Collection]
    var counts: [LibraryListID: Int]
    @Binding var selection: LibraryListID

    var body: some View {
        List(selection: Binding<LibraryListID?>(get: { selection }, set: { selection = $0 ?? .all })) {
            Section("Library") {
                row("Reading", symbol: "book", list: .reading)
                row("Want to Read", symbol: "bookmark", list: .wantToRead)
                row("Read", symbol: "checkmark.circle", list: .read)
                row("All Books", symbol: "books.vertical", list: .all)
            }
            Section("Collections") {
                if collections.isEmpty && !model.isCreatingCollection {
                    Text("Group books your way, like \u{201C}Read in 2026\u{201D}.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(collections) { collection in
                    CollectionRow(model: model, collection: collection, count: counts[.collection(collection.id)] ?? 0)
                        .tag(LibraryListID.collection(collection.id))
                }
                .onMove { offsets, destination in
                    model.attempt { try library?.moveCollections(fromOffsets: offsets, toOffset: destination) }
                }
                if model.isCreatingCollection {
                    NewCollectionRow(model: model)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    model.isCreatingCollection = true
                } label: {
                    Label("New Collection", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func row(_ title: LocalizedStringKey, symbol: String, list: LibraryListID) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(counts[list] ?? 0, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .tag(list)
    }
}

/// The inline name field for a new collection at the end of the list.
struct NewCollectionRow: View {
    var model: WindowModel
    @Environment(\.library) private var library
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        CollectionNameField(
            text: $name, error: error,
            onSubmit: {
                guard let library else { return }
                if let problem = library.validateCollectionName(name) {
                    error = problem.localizedDescription
                    return
                }
                do {
                    let created = try library.createCollection(named: name)
                    model.isCreatingCollection = false
                    model.selectedBookID = nil
                    NotificationCenter.default.post(name: .selectCollection, object: created.id)
                } catch {
                    self.error = error.localizedDescription
                }
            },
            onCancel: { model.isCreatingCollection = false }
        )
    }
}

extension Notification.Name {
    /// Posted with a collection id after it was created, so the window can select it.
    static let selectCollection = Notification.Name("local.buchhalter.selectCollection")
}
