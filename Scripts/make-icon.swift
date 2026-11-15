// Draws the app icon (design variant B, "Shelf") into an .iconset folder:
// four book spines in the generated-cover colours on the accent green, the
// last one leaning.
//
// Usage: swift Scripts/make-icon.swift <output.iconset>
// `make icon` runs it and turns the iconset into Resources/AppIcon.icns.
//
// The artwork is full-bleed and opaque: no rounded corners and no transparent
// margin. macOS 26 and later mask a full-bleed icon to their own rounded
// square; an icon with its own margin is shrunk onto a grey plate instead.
// Mac-only build tool, not part of the app.

import AppKit

// MARK: Colours (from the design canvas and the cover palette)

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

let green = color(0x1F6F5C)
let shelf = color(0x14503F)
let cream = color(0xF4EFE4)
let clay = color(0xB8663A)
let blue = color(0x2E4A62)
let gold = color(0xC9A227)
let band = color(0xE8D9B0)

// MARK: Drawing

/// Draws the icon into a square of `size` pixels. Coordinates follow the
/// design's 100-unit grid with y pointing down. Small sizes leave out the
/// shelf and the spine bands, as the design shows.
func drawIcon(size: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 100
    // Flip so the design's y-down coordinates apply.
    let transform = NSAffineTransform()
    transform.translateX(by: 0, yBy: CGFloat(size))
    transform.scaleX(by: scale, yBy: -scale)
    transform.concat()

    func spine(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: NSColor) {
        fill.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: 1.5, yRadius: 1.5).fill()
    }

    green.setFill()
    NSRect(x: 0, y: 0, width: 100, height: 100).fill()

    let detailed = size >= 64
    if detailed {
        shelf.setFill()
        NSBezierPath(roundedRect: NSRect(x: 16, y: 76, width: 68, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    }

    spine(20, 30, 11.5, 46, cream)
    spine(33.5, 22, 10.5, 54, clay)
    spine(46, 34, 12.5, 42, blue)
    if detailed {
        gold.setFill()
        NSRect(x: 20, y: 36, width: 11.5, height: 2).fill()
        band.setFill()
        NSRect(x: 46, y: 40, width: 12.5, height: 2).fill()
    }

    // The last spine leans left against the blue one, pivoting on its
    // bottom-left corner; at 14° its left edge meets the blue spine's top corner.
    NSGraphicsContext.saveGraphicsState()
    let lean = NSAffineTransform()
    lean.translateX(by: 69, yBy: 76)
    lean.rotate(byDegrees: -14)
    lean.translateX(by: -69, yBy: -76)
    lean.concat()
    spine(69, 26, 10.5, 50, gold)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: Iconset

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift make-icon.swift <output.iconset>\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// iconutil expects these names: 16…512 at 1x and 2x.
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = points * factor
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        guard let rep = drawIcon(size: pixels), let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("could not draw \(name)\n".utf8))
            exit(1)
        }
        try png.write(to: output.appendingPathComponent(name))
    }
}
