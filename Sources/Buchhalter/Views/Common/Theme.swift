import SwiftUI
import BuchhalterCore

/// The app's visual language, from the design: one deep green accent, serif
/// titles in New York, a fixed set of generated cover colours.
enum Theme {
    static let accent = Color(hex: 0x1F6F5C)
    /// Selection and badge background, and its text colour.
    static let tint = Color(hex: 0xDCEBE6)
    static let tintText = Color(hex: 0x14503F)
    static let error = Color(hex: 0xB3261E)

    static func coverColor(for id: UUID) -> Color {
        Color(hex: CoverPalette.color(for: id))
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
