import SwiftUI
import ImageIO

/// Google's "powered by Google" graphic, which its branding rules require
/// next to Google Books results. The official PNG is bundled by `make app`
/// (`Resources/PoweredByGoogle.png`) and loaded through ImageIO, so the view
/// needs no AppKit. It sits on a white plate because the graphic is made for
/// a light background. Without the file nothing is drawn.
struct PoweredByGoogleMark: View {
    private static let image: CGImage? = {
        guard let url = Bundle.main.url(forResource: "PoweredByGoogle", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    var body: some View {
        if let image = Self.image {
            Image(image, scale: 1, label: Text(verbatim: "powered by Google"))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.white, in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.25)) }
        }
    }
}
