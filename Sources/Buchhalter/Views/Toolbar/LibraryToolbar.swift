import SwiftUI
import BuchhalterCore

/// The Sort button with its popover.
struct SortButton: View {
    @Environment(\.locale) private var locale
    var listName: String
    var levels: SortLevels
    var onChange: (SortLevels) -> Void
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Label(BookFormatting(locale: locale).sortButtonLabel(levels), systemImage: "arrow.up.arrow.down")
        }
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            SortPopover(listName: listName, levels: levels, onChange: onChange)
        }
        .help("Sort")
    }
}

/// Sort button, List/Grid switch and `+`. The title, count and search field
/// come from the navigation title, subtitle and `.searchable`.
struct LibraryToolbar: ToolbarContent {
    var listName: String
    var preferences: ListPreferences
    var onSort: (SortLevels) -> Void
    var onViewMode: (ViewMode) -> Void
    var onAdd: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            SortButton(listName: listName, levels: preferences.sortLevels, onChange: onSort)
        }
        ToolbarItem(placement: .automatic) {
            Picker("View", selection: Binding(get: { preferences.viewMode }, set: { onViewMode($0) })) {
                Label("List", systemImage: "list.bullet").tag(ViewMode.list)
                Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("View")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: onAdd) {
                Label("Add Book", systemImage: "plus")
            }
            .help("Add Book")
        }
    }
}
