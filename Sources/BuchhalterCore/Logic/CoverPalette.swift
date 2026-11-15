import Foundation

/// The colours of generated covers. A book's colour comes from its synced
/// `UUID`, so every device shows the same one. `Hasher` is seeded per launch
/// and must not be used here.
public enum CoverPalette {
    public static let colors: [UInt32] = [
        0x2E4A62, 0x8A5A2B, 0x3F6B4E, 0x6B3F5E, 0xA0522D, 0x5A6B2E,
        0x5E4B8A, 0x2F5F7A, 0x4A4F57, 0x7A2E3A, 0x3A6B6B,
    ]

    public static func index(for id: UUID) -> Int {
        var hash: UInt32 = 2_166_136_261
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt32(byte)
                hash = hash &* 16_777_619
            }
        }
        return Int(hash % UInt32(colors.count))
    }

    public static func color(for id: UUID) -> UInt32 { colors[index(for: id)] }
}
