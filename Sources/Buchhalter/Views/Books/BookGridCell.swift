import SwiftUI
import BuchhalterCore

/// One book in the grid: a 2:3 cover, title, author, stars or "No rating".
struct BookGridCell: View {
    var book: Book
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                CoverView(book: book, size: CGSize(width: proxy.size.width, height: proxy.size.width * 1.5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Theme.accent, lineWidth: isSelected ? 3 : 0)
                    }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            Text(book.title)
                .font(Theme.serif(13))
                .lineLimit(2)
            let authors = book.orderedAuthors.map(\.name).joined(separator: ", ")
            if !authors.isEmpty {
                Text(authors)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let rating = book.displayRating {
                StarRatingView(rating: rating)
            } else {
                Text("No rating")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
