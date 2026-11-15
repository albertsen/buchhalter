import SwiftUI

/// Read-only stars: filled in the accent colour, the rest grey.
struct StarRatingView: View {
    var rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: "star.fill")
                    .foregroundStyle(star <= rating ? Theme.accent : Color.secondary.opacity(0.35))
            }
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating) of 5")
    }
}

/// Five stars to click, with Clear.
struct StarRatingControl: View {
    @Binding var rating: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = star
                } label: {
                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                        .foregroundStyle(star <= (rating ?? 0) ? Theme.accent : Color.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) stars")
                .accessibilityAddTraits(rating == star ? .isSelected : [])
            }
            Button("Clear") { rating = nil }
                .buttonStyle(.link)
                .disabled(rating == nil)
                .padding(.leading, 8)
        }
    }
}
