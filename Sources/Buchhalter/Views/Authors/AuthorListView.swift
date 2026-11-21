import SwiftUI
import BuchhalterCore

/// The authors, under the letters of their sort names, in the middle column.
/// Choosing one opens their books on the right (collapsed on the iPhone: pushes them).
struct AuthorListView: View {
    var model: WindowModel
    var sections: [AuthorSection]
    var selection: Binding<UUID?>

    var body: some View {
        List(selection: selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.authors) { entry in
                        AuthorRow(entry: entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button("Edit Sorted As…") { model.sheet = .editSortName(entry.id) }
                            }
                    }
                } header: {
                    Text(verbatim: section.letter)
                }
                #if os(iOS)
                .sectionIndexLabel(section.letter)
                #endif
            }
        }
        #if os(iOS)
        // Plain like the book lists, with the system's A–Z index.
        .listStyle(.plain)
        .listSectionIndexVisibility(.visible)
        #endif
        .accessibilityLabel("Authors")
    }
}

/// The name as written and the number of the author's books.
struct AuthorRow: View {
    var entry: AuthorEntry

    var body: some View {
        HStack {
            Text(entry.name)
            Spacer()
            Text(entry.bookCount, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
