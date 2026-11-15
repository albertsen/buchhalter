import SwiftUI
import BuchhalterCore

/// The collections a book is in, and a menu to add it to more.
struct CollectionChips: View {
    @Environment(\.library) private var library
    var model: WindowModel
    var book: Book
    var collections: [Collection]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collections")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach((book.collections ?? []).sorted { $0.sortIndex < $1.sortIndex }) { collection in
                    Chip { Text(collection.name) }
                }
                Menu {
                    ForEach(collections) { collection in
                        let isMember = (book.collections ?? []).contains { $0 === collection }
                        Toggle(collection.name, isOn: Binding(
                            get: { isMember },
                            set: { _ in model.attempt { try library?.toggle(book, in: collection) } }
                        ))
                    }
                    if !collections.isEmpty { Divider() }
                    Button("New Collection…") { model.sheet = .newCollection(addingBook: book.id) }
                } label: {
                    Chip(dashed: true) { Text("+ Add to Collection") }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }
}

/// Wraps its children onto new lines, as the chips in the design do.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
