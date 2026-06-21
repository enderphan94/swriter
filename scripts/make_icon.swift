import AppKit

// Draws Swriter's app icon — a warm "page" tile with a writing nib — to a 1024
// PNG. Invoked by build.sh as: swift scripts/make_icon.swift <out.png>
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let side: CGFloat = 1024

let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

// Tile, inset a little so it floats on the icon grid.
let inset: CGFloat = 80
let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let radius = rect.width * 0.225
let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

let cream = NSColor(srgbRed: 0.969, green: 0.937, blue: 0.851, alpha: 1)
let tan   = NSColor(srgbRed: 0.914, green: 0.847, blue: 0.690, alpha: 1)
if let gradient = NSGradient(starting: cream, ending: tan) {
    gradient.draw(in: tile, angle: -55)
}
NSColor.black.withAlphaComponent(0.08).setStroke()
tile.lineWidth = 3
tile.stroke()

// Pencil nib, tinted in the same warm brown as the in-app glyph.
let ink = NSColor(srgbRed: 0.357, green: 0.275, blue: 0.212, alpha: 1)
let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .medium)
    .applying(NSImage.SymbolConfiguration(hierarchicalColor: ink))
if let symbol = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    let target = NSRect(x: (side - s.width) / 2, y: (side - s.height) / 2,
                        width: s.width, height: s.height)
    symbol.draw(in: target)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon: failed to render PNG\n".utf8))
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write(Data("icon: \(error)\n".utf8))
    exit(1)
}
