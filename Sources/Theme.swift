import SwiftUI
import AppKit

/// Three deliberate writing surfaces. A writing app lives and dies by the
/// colour of its paper, so the theme is chosen explicitly rather than tracking
/// the system — Light for daytime, Sepia for long reading sessions, Dark for
/// night. Each is a fixed palette so the editor's syntax styling stays legible.
enum WriterTheme: String, CaseIterable, Identifiable {
    case light, sepia, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .dark:  return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .light: return "sun.max"
        case .sepia: return "book.closed"
        case .dark:  return "moon"
        }
    }

    /// Drives SwiftUI's rendering of native chrome (menus, sheets, fields).
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }

    // MARK: Palette (AppKit, for the NSTextView editor)

    /// The page itself.
    var background: NSColor {
        switch self {
        case .light: return NSColor(srgb: 0xFCFCFA)
        case .sepia: return NSColor(srgb: 0xFBF0D9)
        case .dark:  return NSColor(srgb: 0x1B1B1D)
        }
    }

    /// Body text — the ink.
    var text: NSColor {
        switch self {
        case .light: return NSColor(srgb: 0x1A1A1A)
        case .sepia: return NSColor(srgb: 0x5B4636)
        case .dark:  return NSColor(srgb: 0xD9D9D4)
        }
    }

    /// Markdown punctuation (`**`, `#`, `>`…) — present but quiet, the way iA
    /// Writer keeps the syntax visible yet out of the way.
    var faint: NSColor {
        switch self {
        case .light: return NSColor(srgb: 0xBFBFBA)
        case .sepia: return NSColor(srgb: 0xB9A88F)
        case .dark:  return NSColor(srgb: 0x5C5C60)
        }
    }

    /// Text outside the focused sentence/paragraph in Focus mode.
    var dimmed: NSColor {
        switch self {
        case .light: return NSColor(srgb: 0xC8C8C4)
        case .sepia: return NSColor(srgb: 0xC3B49C)
        case .dark:  return NSColor(srgb: 0x65656A)
        }
    }

    /// Links and the heading accent.
    var accent: NSColor {
        switch self {
        case .light: return NSColor(srgb: 0x2E6BE6)
        case .sepia: return NSColor(srgb: 0x9A6A2F)
        case .dark:  return NSColor(srgb: 0x6FA0FF)
        }
    }

    /// Inline-code / code-block tint.
    var codeBackground: NSColor {
        switch self {
        case .light: return NSColor(srgb: 0x1A1A1A, alpha: 0.06)
        case .sepia: return NSColor(srgb: 0x5B4636, alpha: 0.08)
        case .dark:  return NSColor(srgb: 0xFFFFFF, alpha: 0.07)
        }
    }

    var selection: NSColor { accent.withAlphaComponent(0.22) }

    // MARK: SwiftUI mirrors (for the chrome)

    var bg: Color { Color(nsColor: background) }
    var ink: Color { Color(nsColor: text) }
    var faintColor: Color { Color(nsColor: faint) }
    var accentColor: Color { Color(nsColor: accent) }
}

/// Font choices. The editor is monospaced for the iA-Writer feel; reading and
/// print use a serif so finished prose looks like a book page.
enum Typeface {
    static func editor(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func editorBold(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
    }

    /// New York (the system serif) where available, Georgia as a fallback.
    static func serif(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.serif) {
            return NSFont(descriptor: d, size: size) ?? base
        }
        return NSFont(name: "Georgia", size: size) ?? base
    }

    static func serifItalic(_ size: CGFloat) -> NSFont {
        let serif = self.serif(size)
        let d = serif.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: d, size: size) ?? serif
    }

    static func mono(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

extension NSColor {
    /// Build a colour from a 0xRRGGBB literal in the sRGB space.
    convenience init(srgb hex: Int, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green:    CGFloat((hex >> 8) & 0xFF) / 255,
                  blue:     CGFloat(hex & 0xFF) / 255,
                  alpha:    alpha)
    }
}
