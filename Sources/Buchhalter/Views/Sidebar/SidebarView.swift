import SwiftUI
import BuchhalterCore

/// The Library lists and the user's collections, with counts.
struct SidebarView: View {
    @Environment(\.library) private var library
    var model: WindowModel
    var collections: [Collection]
    var counts: [LibraryListID: Int]
    /// Where the order of the built-in lists lives (a `ListSettings` row that syncs).
    var settings: [ListSettings]
    @Binding var selection: LibraryListID
    @Environment(CloudSyncMonitor.self) private var syncMonitor

    /// The user's order of the four built-in lists (`LibraryListOrder`).
    private var libraryOrder: LibraryListOrder { ListSettings.libraryListOrder(among: settings) }

    var body: some View {
        // A click on empty space deselects; the list stays as it was.
        List(selection: Binding<LibraryListID?>(get: { selection }, set: { if let list = $0 { selection = list } })) {
            Section("Library") {
                ForEach(libraryOrder.lists, id: \.self) { list in
                    builtInRow(list)
                }
                .onMove { offsets, destination in
                    var order = libraryOrder
                    order.move(fromOffsets: offsets, toOffset: destination)
                    model.attempt { try library?.setLibraryListOrder(order) }
                }
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
            VStack(alignment: .leading, spacing: 8) {
                if let line = syncMonitor.state.sidebarLine {
                    SidebarSyncLine(line: line, isError: isFailure)
                }
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    /// Sync stopped for a reason other than sign-in or storage: the line is red.
    private var isFailure: Bool {
        if case .failed = syncMonitor.state.problem { return true }
        return false
    }

    @ViewBuilder
    private func builtInRow(_ list: LibraryListID) -> some View {
        switch list {
        case .reading: row("Reading", symbol: "book", list: .reading)
        case .wantToRead: row("Want to Read", symbol: "bookmark", list: .wantToRead)
        case .read: row("Read", symbol: "checkmark.circle", list: .read)
        case .all: row("All Books", symbol: "books.vertical", list: .all)
        case .collection: EmptyView()
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
