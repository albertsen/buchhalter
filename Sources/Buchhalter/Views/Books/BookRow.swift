import SwiftUI
import BuchhalterCore

/// One book in the list: small cover, serif title, author, status line.
struct BookRow: View {
    @Environment(\.locale) private var locale
    var book: Book
    var isSelected: Bool
    /// Shown in place of the authors, among an author's books ("1959 · with
    /// Lisa Seidl"). Nil shows the authors; an empty line shows nothing.
    var lineInsteadOfAuthors: String? = nil

    var body: some View {
        let formatting = BookFormatting(locale: locale)
        HStack(alignment: .top, spacing: 12) {
            CoverView(book: book, size: CGSize(width: 40, height: 58))
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(Theme.serif(15))
                    .lineLimit(2)
                let second = lineInsteadOfAuthors ?? book.orderedAuthors.map(\.name).joined(separator: ", ")
                if !second.isEmpty {
                    Text(second)
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                if let reading = book.currentReading, let line = formatting.statusLine(reading) {
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
