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

    // Book lookup. A filled field is the accent at low opacity over whatever
    // the field draws, so it reads in light and dark mode.
    static let filledFill = accent.opacity(0.09)
    static let filledBorder = accent.opacity(0.5)
    /// The amber "no book found" hint and the red "can't reach" hint: fixed
    /// background and text pairs, like the green banner (`tint`, `tintText`).
    static let warningFill = Color(hex: 0xFDF1DC)
    static let warningText = Color(hex: 0x6B4A00)
    static let errorFill = Color(hex: 0xFBE4E2)
    static let errorText = Color(hex: 0x8C1D16)

    // Barcode scanning: the frame and capsule colours over the camera picture
    // (fixed, like the picture's dark background).
    static let scanGreen = Color(hex: 0x3FBF8F)
    static let scanAmber = Color(hex: 0xE0A33A)
    static let scanAmberFill = Color(hex: 0xF6D58E)
    static let scanAmberText = Color(hex: 0x3A2A00)

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
