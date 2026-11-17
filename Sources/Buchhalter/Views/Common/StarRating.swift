import SwiftUI
import BuchhalterCore

/// Read-only stars in half steps: filled in the accent colour, the rest grey.
struct StarRatingView: View {
    @Environment(\.locale) private var locale
    /// 0.5 to 5.0.
    var rating: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: StarSymbol.name(for: star, rating: rating))
                    .foregroundStyle(Double(star) - 0.5 <= rating ? Theme.accent : Color.secondary.opacity(0.35))
            }
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BookFormatting(locale: locale).rated(rating))
    }
}

/// Five stars to click, with Clear. A click on a star gives it whole (4); a
/// second click on the same star makes it half (3.5), a third whole again.
/// The arrow keys and VoiceOver adjust in half steps.
struct StarRatingControl: View {
    @Environment(\.locale) private var locale
    @Binding var rating: Double?

    private let starSize: CGFloat = 16
    private let spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: spacing) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: StarSymbol.name(for: star, rating: rating ?? 0, outline: true))
                        .foregroundStyle(Double(star) - 0.5 <= (rating ?? 0) ? Theme.accent : Color.secondary)
                        .font(.system(size: starSize))
                        .frame(width: starSize + 2, height: starSize + 2)
                        .contentShape(Rectangle())
                        .onTapGesture { rating = StarClick.rating(afterClicking: star, current: rating) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Rating"))
            .accessibilityValue(rating.map { BookFormatting(locale: locale).stars($0) } ?? String(localized: "No rating"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: rating = min(5, (rating ?? 0) + 0.5)
                case .decrement: rating = (rating ?? 0) <= 0.5 ? nil : (rating ?? 0) - 0.5
                @unknown default: break
                }
            }
            .focusable()
            .onKeyPress(.rightArrow) {
                rating = min(5, (rating ?? 0) + 0.5)
                return .handled
            }
            .onKeyPress(.leftArrow) {
                rating = (rating ?? 0) <= 0.5 ? nil : (rating ?? 0) - 0.5
                return .handled
            }
            Button("Clear") { rating = nil }
                .linkButtonStyle()
                .disabled(rating == nil)
        }
    }
}

/// The SF Symbol for one star at a rating: full, half or empty.
private enum StarSymbol {
    static func name(for star: Int, rating: Double, outline: Bool = false) -> String {
        if Double(star) <= rating { return "star.fill" }
        if Double(star) - 0.5 <= rating { return "star.leadinghalf.filled" }
        return outline ? "star" : "star.fill"
    }
}
