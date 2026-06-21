import AppKit

/// Live, in-place Markdown styling for the editor — the iA-Writer trick of
/// keeping the raw syntax on screen but quieting it: `**` stays visible yet
/// faint, while the words between turn bold. Operates directly on the text
/// view's `NSTextStorage` so the user always edits plain text.
enum MarkdownHighlighter {

    // Compile each pattern once.
    private static func rx(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
    }
    private static let heading   = rx("^(#{1,6})[ \t]+(.+)$")
    private static let quote     = rx("^[ \t]*(>[ \t]?)(.*)$")
    private static let listItem  = rx("^([ \t]*)([-*+]|\\d+[.)])[ \t]+")
    private static let hrule      = rx("^[ \t]*([-*_])([ \t]*\\1){2,}[ \t]*$")
    private static let boldItalic = rx("(\\*\\*\\*)(.+?)(\\*\\*\\*)")
    private static let bold       = rx("(\\*\\*|__)(.+?)(\\1)")
    private static let italic     = rx("(?<![\\*_])([*_])(?![ *_])(.+?)(?<![ *_])(\\1)(?![\\*_])")
    private static let strike     = rx("(~~)(.+?)(~~)")
    private static let code       = rx("(`)([^`\n]+)(`)")
    private static let link       = rx("(\\[)([^\\]\n]+)(\\]\\()([^)\n]+)(\\))")

    /// Re-style the whole document. Cheap enough for note- and chapter-sized
    /// text; called after each edit and on theme/font changes.
    static func apply(to storage: NSTextStorage, theme: WriterTheme, size: CGFloat) {
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: ns.length)

        let body = Typeface.editor(size)
        let bodyBold = Typeface.editorBold(size)

        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.32
        para.paragraphSpacing = size * 0.55

        storage.beginEditing()
        defer { storage.endEditing() }

        // 1. Base layer — body font, ink, comfortable leading.
        storage.setAttributes([
            .font: body,
            .foregroundColor: theme.text,
            .paragraphStyle: para,
        ], range: full)

        // 2. Fenced code blocks (``` … ```), tracked so inline rules skip them.
        let codeRanges = styleFencedCode(storage, ns: ns, theme: theme, size: size)

        // 3. Line-level blocks.
        heading.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m, let hashes = range(m, 1), let titleR = range(m, 2) else { return }
            let level = hashes.length
            let scale: CGFloat = [1.7, 1.45, 1.28, 1.16, 1.08, 1.03][min(level - 1, 5)]
            let hFont = Typeface.editorBold(size * scale)
            let whole = m.range
            let hPara = NSMutableParagraphStyle()
            hPara.lineHeightMultiple = 1.2
            hPara.paragraphSpacing = size * 0.45
            hPara.paragraphSpacingBefore = size * 0.9
            storage.addAttribute(.paragraphStyle, value: hPara, range: whole)
            storage.addAttributes([.font: hFont, .foregroundColor: theme.text], range: titleR)
            storage.addAttributes([.font: Typeface.editor(size * scale),
                                   .foregroundColor: theme.faint], range: hashes)
        }

        quote.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m, let mark = range(m, 1), let txt = range(m, 2) else { return }
            storage.addAttribute(.foregroundColor, value: theme.faint, range: mark)
            storage.addAttributes([.foregroundColor: theme.text.withAlphaComponent(0.8),
                                   .font: Typeface.mono(size)], range: txt)
        }

        listItem.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m, let marker = range(m, 2) else { return }
            storage.addAttributes([.foregroundColor: theme.accent, .font: bodyBold], range: marker)
        }

        hrule.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: theme.faint, range: m.range)
        }

        // 4. Inline spans (skip anything inside a code fence).
        func inline(_ re: NSRegularExpression, marks: [Int], content: Int, font: NSFont? = nil,
                    color: NSColor? = nil, extra: [NSAttributedString.Key: Any] = [:]) {
            re.enumerateMatches(in: storage.string, range: full) { m, _, _ in
                guard let m, !intersects(m.range, codeRanges) else { return }
                for g in marks {
                    if let r = range(m, g) {
                        storage.addAttribute(.foregroundColor, value: theme.faint, range: r)
                    }
                }
                if let r = range(m, content) {
                    if let font { storage.addAttribute(.font, value: font, range: r) }
                    if let color { storage.addAttribute(.foregroundColor, value: color, range: r) }
                    for (k, v) in extra { storage.addAttribute(k, value: v, range: r) }
                }
            }
        }

        inline(code, marks: [1, 3], content: 2, color: theme.text,
               extra: [.backgroundColor: theme.codeBackground])
        inline(boldItalic, marks: [1, 3], content: 2, font: boldItalic_font(size))
        inline(bold, marks: [1, 3], content: 2, font: bodyBold)
        inline(italic, marks: [1, 3], content: 2, font: italicFont(size))
        inline(strike, marks: [1, 3], content: 2,
               extra: [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                       .strikethroughColor: theme.text])

        // Links: [text](url) — text in accent, the (url) faint.
        link.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m, !intersects(m.range, codeRanges) else { return }
            if let b1 = range(m, 1) { storage.addAttribute(.foregroundColor, value: theme.faint, range: b1) }
            if let label = range(m, 2) {
                storage.addAttributes([.foregroundColor: theme.accent,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue], range: label)
            }
            if let b2 = range(m, 3) { storage.addAttribute(.foregroundColor, value: theme.faint, range: b2) }
            if let url = range(m, 4) { storage.addAttribute(.foregroundColor, value: theme.faint, range: url) }
            if let b3 = range(m, 5) { storage.addAttribute(.foregroundColor, value: theme.faint, range: b3) }
        }
    }

    // MARK: Focus mode

    /// Dim everything but the paragraph holding the cursor, then restore that
    /// paragraph's real styling. Call after `apply` (and on selection changes).
    static func applyFocus(to storage: NSTextStorage, selection: NSRange,
                           theme: WriterTheme, size: CGFloat) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }
        let full = NSRange(location: 0, length: ns.length)
        let clamped = NSRange(location: min(selection.location, ns.length), length: 0)
        let focus = ns.paragraphRange(for: clamped)

        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: theme.dimmed, range: full)
        storage.endEditing()
        // Re-color just the focused paragraph by re-running the full styler on it
        // would be heavy; instead re-apply the document styler and then dim the
        // rest. Simpler: restyle all, then dim outside focus.
        restoreColors(storage, theme: theme, size: size, except: focus)
    }

    /// Re-run styling but force every glyph *outside* `keep` to the dim colour.
    private static func restoreColors(_ storage: NSTextStorage, theme: WriterTheme,
                                      size: CGFloat, except keep: NSRange) {
        apply(to: storage, theme: theme, size: size)
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        storage.beginEditing()
        if keep.location > 0 {
            storage.addAttribute(.foregroundColor, value: theme.dimmed,
                                 range: NSRange(location: 0, length: keep.location))
        }
        let tail = keep.location + keep.length
        if tail < full.length {
            storage.addAttribute(.foregroundColor, value: theme.dimmed,
                                 range: NSRange(location: tail, length: full.length - tail))
        }
        storage.endEditing()
    }

    // MARK: Helpers

    private static func styleFencedCode(_ storage: NSTextStorage, ns: NSString,
                                        theme: WriterTheme, size: CGFloat) -> [NSRange] {
        var ranges: [NSRange] = []
        var inBlock = false
        var blockStart = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if inBlock {
                    let end = lineRange.location + lineRange.length
                    ranges.append(NSRange(location: blockStart, length: end - blockStart))
                    inBlock = false
                } else {
                    inBlock = true
                    blockStart = lineRange.location
                }
            }
        }
        if inBlock { ranges.append(NSRange(location: blockStart, length: ns.length - blockStart)) }
        let mono = Typeface.mono(size)
        for r in ranges {
            storage.addAttributes([.font: mono, .foregroundColor: theme.text,
                                   .backgroundColor: theme.codeBackground], range: r)
        }
        return ranges
    }

    private static func italicFont(_ size: CGFloat) -> NSFont {
        let base = Typeface.editor(size)
        let d = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: d, size: size) ?? base
    }

    private static func boldItalic_font(_ size: CGFloat) -> NSFont {
        let base = Typeface.editorBold(size)
        let d = base.fontDescriptor.withSymbolicTraits([.italic, .bold])
        return NSFont(descriptor: d, size: size) ?? base
    }

    private static func range(_ m: NSTextCheckingResult, _ i: Int) -> NSRange? {
        guard i < m.numberOfRanges else { return nil }
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : r
    }

    private static func intersects(_ r: NSRange, _ ranges: [NSRange]) -> Bool {
        for x in ranges where NSIntersectionRange(r, x).length > 0 { return true }
        return false
    }
}
