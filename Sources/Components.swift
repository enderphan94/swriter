import SwiftUI

/// The app's mark — a warm "page" tile with a writing nib. Used in the About
/// panel and the welcome screen so they share the bundled icon's character
/// without loading a raster asset.
struct AppGlyph: View {
    var size: CGFloat = 72

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(srgb: 0xF7EFD9), Color(srgb: 0xE9D8B0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                Image(systemName: "pencil.line")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(Color(srgb: 0x5B4636))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.12), radius: size * 0.06, y: size * 0.03)
    }
}

extension Color {
    init(srgb hex: Int) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255)
    }
}
