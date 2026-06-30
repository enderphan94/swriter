import AppKit

/// The bridge that lets people write visually while the file stays Markdown.
///
/// `parse` turns Markdown into an *editable* attributed string where structure
/// is carried by semantic attributes (not visible symbols): each paragraph has
/// a `.swBlock`, emphasis is flagged with `.swBold` / `.swItalic` / … , and
/// images are real attachments. `serialize` walks that attributed string back
/// to Markdown.
///
/// Decoupling meaning (the flags) from appearance (the fonts) is what makes the
/// round-trip safe: a heading looks bold but carries no bold *flag*, so it never
/// gains stray `**`. Anything we don't model (tables, HTML) is kept verbatim as
/// a `.raw` block so it can never be corrupted.
enum RichMarkdown {

    // MARK: Semantic attributes

    enum Key {
        static let block = NSAttributedString.Key("swBlock")     // BlockKind.code
        static let bold = NSAttributedString.Key("swBold")
        static let italic = NSAttributedString.Key("swItalic")
        static let strike = NSAttributedString.Key("swStrike")
        static let code = NSAttributedString.Key("swCode")       // inline code
        static let indent = NSAttributedString.Key("swIndent")   // list depth (Int)
        static let number = NSAttributedString.Key("swNumber")   // ordered-list number (Int)
        static let lang = NSAttributedString.Key("swLang")       // code-fence language
        static let imagePath = NSAttributedString.Key("swImagePath")
        static let imageAlt = NSAttributedString.Key("swImageAlt")
        static let tableSource = NSAttributedString.Key("swTableSource") // verbatim Markdown of a rendered table
    }

    enum BlockKind: Equatable {
        case paragraph, heading(Int), bullet, ordered, quote, code, rule, raw

        var encoded: String {
            switch self {
            case .paragraph: return "p"
            case .heading(let n): return "h\(n)"
            case .bullet: return "ul"
            case .ordered: return "ol"
            case .quote: return "quote"
            case .code: return "code"
            case .rule: return "hr"
            case .raw: return "raw"
            }
        }

        static func decode(_ s: String?) -> BlockKind {
            guard let s else { return .paragraph }
            switch s {
            case "ul": return .bullet
            case "ol": return .ordered
            case "quote": return .quote
            case "code": return .code
            case "hr": return .rule
            case "raw": return .raw
            default:
                if s.hasPrefix("h"), let n = Int(s.dropFirst()) { return .heading(n) }
                return .paragraph
            }
        }
    }

    // MARK: Fonts (appearance derived from block + inline flags)

    static func font(block: BlockKind, bold: Bool, italic: Bool, code: Bool, size: CGFloat) -> NSFont {
        if code || block == .code || block == .raw {
            return NSFont.monospacedSystemFont(ofSize: size * 0.94, weight: .regular)
        }
        var pt = size
        var baseBold = false
        if case .heading(let lvl) = block {
            pt = size * [1.7, 1.45, 1.28, 1.16, 1.08, 1.03][min(max(lvl, 1), 6) - 1]
            baseBold = true
        }
        var f = NSFont.systemFont(ofSize: pt, weight: (bold || baseBold) ? .bold : .regular)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold || baseBold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        if !traits.isEmpty {
            let d = f.fontDescriptor.withSymbolicTraits(traits)
            f = NSFont(descriptor: d, size: pt) ?? f
        }
        return f
    }

    static func paragraphStyle(_ block: BlockKind, indent: Int, size: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.25
        p.paragraphSpacing = size * 0.55
        switch block {
        case .heading:
            p.paragraphSpacingBefore = size * 0.8
            p.paragraphSpacing = size * 0.35
        case .bullet, .ordered:
            // Text aligns at `base`; the marker is drawn by RichLayoutManager in
            // the margin to its left, so it never enters the saved Markdown.
            let base = size * (1.6 + CGFloat(indent) * 1.4)
            p.firstLineHeadIndent = base
            p.headIndent = base
            p.paragraphSpacing = size * 0.2
        case .quote:
            p.firstLineHeadIndent = size * 1.2
            p.headIndent = size * 1.2
        case .code, .raw:
            p.firstLineHeadIndent = size
            p.headIndent = size
            p.paragraphSpacing = 0
            p.lineHeightMultiple = 1.15
        default: break
        }
        return p
    }

    // MARK: Parse — Markdown → editable attributed string

    static func parse(_ markdown: String, theme: WriterTheme, size: CGFloat, baseURL: URL?) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: .whitespaces)

            // Fenced code block → one .code paragraph per line (grouped back on save).
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                let fence = String(t.prefix(3))
                let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    appendBlockLine(out, text: lines[i], block: .code, theme: theme, size: size, lang: lang)
                    i += 1
                }
                i += 1 // closing fence
                continue
            }

            // Table (header + separator + rows) → render as a real grid, but
            // keep the exact source so saving never alters it. Edit in Source mode.
            if isTableRow(t), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                var rows: [String] = [raw, lines[i + 1]]
                i += 2
                while i < lines.count {
                    let r = lines[i].trimmingCharacters(in: .whitespaces)
                    guard r.contains("|"), !r.isEmpty else { break }
                    rows.append(lines[i]); i += 1
                }
                appendTable(out, source: rows.joined(separator: "\n"), theme: theme, size: size)
                continue
            }

            // HTML or a stray table-ish line → keep verbatim as a raw line.
            if isTableRow(t) || t.hasPrefix("<") {
                appendBlockLine(out, text: raw, block: .raw, theme: theme, size: size)
                i += 1
                continue
            }

            if t.isEmpty {
                appendParagraph(out, inline: NSAttributedString(), block: .paragraph, theme: theme, size: size)
                i += 1; continue
            }
            if let (lvl, text) = heading(t) {
                appendParagraph(out, inline: inline(text, theme: theme, size: size, block: .heading(lvl), baseURL: baseURL),
                                block: .heading(lvl), theme: theme, size: size)
                i += 1; continue
            }
            if isRule(t) {
                appendParagraph(out, inline: NSAttributedString(string: "—"), block: .rule, theme: theme, size: size)
                i += 1; continue
            }
            if let q = stripQuote(t) {
                appendParagraph(out, inline: inline(q, theme: theme, size: size, block: .quote, baseURL: baseURL),
                                block: .quote, theme: theme, size: size)
                i += 1; continue
            }
            if let (ordered, depth, number, text) = listItem(raw) {
                let block: BlockKind = ordered ? .ordered : .bullet
                appendParagraph(out, inline: inline(text, theme: theme, size: size, block: block, baseURL: baseURL),
                                block: block, indent: depth, number: number, theme: theme, size: size)
                i += 1; continue
            }
            // Paragraph.
            appendParagraph(out, inline: inline(raw, theme: theme, size: size, block: .paragraph, baseURL: baseURL),
                            block: .paragraph, theme: theme, size: size)
            i += 1
        }
        // Drop the final trailing newline we always add, so an empty doc is empty.
        if out.length > 0 { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        return out
    }

    private static func appendParagraph(_ out: NSMutableAttributedString, inline body: NSAttributedString,
                                        block: BlockKind, indent: Int = 0, number: Int = 0,
                                        theme: WriterTheme, size: CGFloat) {
        let para = NSMutableAttributedString(attributedString: body)
        para.append(NSAttributedString(string: "\n"))
        let full = NSRange(location: 0, length: para.length)
        para.addAttributes([
            Key.block: block.encoded,
            Key.indent: indent,
            .paragraphStyle: paragraphStyle(block, indent: indent, size: size),
        ], range: full)
        if case .ordered = block { para.addAttribute(Key.number, value: number, range: full) }
        // Default font/colour where the inline pass didn't set one (e.g. empty line).
        para.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            if value == nil {
                para.addAttribute(.font, value: font(block: block, bold: false, italic: false, code: false, size: size), range: range)
            }
        }
        para.addAttribute(.foregroundColor, value: blockColor(block, theme: theme), range: full)
        out.append(para)
    }

    private static func appendBlockLine(_ out: NSMutableAttributedString, text: String, block: BlockKind,
                                        theme: WriterTheme, size: CGFloat, lang: String = "") {
        let line = NSMutableAttributedString(string: text + "\n", attributes: [
            Key.block: block.encoded,
            Key.lang: lang,
            .font: font(block: block, bold: false, italic: false, code: false, size: size),
            .foregroundColor: blockColor(block, theme: theme),
            .paragraphStyle: paragraphStyle(block, indent: 0, size: size),
        ])
        out.append(line)
    }

    /// A Markdown table as a rendered-grid attachment carrying its exact source.
    private static func appendTable(_ out: NSMutableAttributedString, source: String,
                                    theme: WriterTheme, size: CGFloat) {
        let att = NSTextAttachment()
        if let (image, sz) = tableImage(source, theme: theme, size: size) {
            att.image = image
            att.bounds = CGRect(origin: .zero, size: sz)
        } else {
            // Couldn't render — fall back to verbatim raw lines so nothing is lost.
            for line in source.components(separatedBy: "\n") {
                appendBlockLine(out, text: line, block: .raw, theme: theme, size: size)
            }
            return
        }
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = size * 0.5
        p.paragraphSpacing = size * 0.6
        let s = NSMutableAttributedString(attachment: att)
        s.append(NSAttributedString(string: "\n"))
        s.addAttributes([Key.block: "table", Key.tableSource: source, .paragraphStyle: p],
                        range: NSRange(location: 0, length: s.length))
        out.append(s)
    }

    /// Render a table's Markdown to a transparent image of an NSTextTable grid,
    /// reusing the reading-mode renderer so emphasis inside cells shows too.
    static func tableImage(_ source: String, theme: WriterTheme, size: CGFloat) -> (NSImage, NSSize)? {
        let attr = MarkdownRenderer.attributed(source, theme: theme, bodySize: size, forPrint: false)
        guard attr.length > 0 else { return nil }
        let storage = NSTextStorage(attributedString: attr)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 640, height: 1_000_000))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        _ = layout.glyphRange(for: container)            // force layout
        let used = layout.usedRect(for: container)
        let sz = NSSize(width: max(1, ceil(used.width)), height: max(1, ceil(used.height)))
        // Draw into a flipped image context (top-left origin) so TextKit lays the
        // table out top-down with upright glyphs, then rasterize it now — while
        // `storage` is still alive — into a static bitmap.
        let range = NSRange(location: 0, length: layout.numberOfGlyphs)
        let drawn = NSImage(size: sz, flipped: true) { _ in
            layout.drawBackground(forGlyphRange: range, at: .zero)
            layout.drawGlyphs(forGlyphRange: range, at: .zero)
            return true
        }
        guard let tiff = drawn.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let image = NSImage(size: sz)
        image.addRepresentation(rep)
        return (image, sz)
    }

    static func blockColor(_ block: BlockKind, theme: WriterTheme) -> NSColor {
        switch block {
        case .quote, .raw: return theme.text.withAlphaComponent(0.7)
        default: return theme.text
        }
    }

    // MARK: Inline parse — emphasis/links/images → flagged runs

    private static func inline(_ s: String, theme: WriterTheme, size: CGFloat,
                               block: BlockKind, baseURL: URL?,
                               bold: Bool = false, italic: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(s)
        var i = 0
        var run = ""

        func attrs(bold: Bool, italic: Bool, code: Bool) -> [NSAttributedString.Key: Any] {
            var a: [NSAttributedString.Key: Any] = [
                .font: font(block: block, bold: bold, italic: italic, code: code, size: size),
                .foregroundColor: blockColor(block, theme: theme),
            ]
            if bold { a[Key.bold] = true }
            if italic { a[Key.italic] = true }
            if code { a[Key.code] = true; a[.backgroundColor] = theme.codeBackground }
            return a
        }
        func flush() {
            if run.isEmpty { return }
            result.append(NSAttributedString(string: run, attributes: attrs(bold: bold, italic: italic, code: false)))
            run = ""
        }
        func find(_ token: [Character], from: Int) -> Int? {
            guard token.count > 0, from <= chars.count - token.count else { return nil }
            var k = from
            while k <= chars.count - token.count {
                if Array(chars[k..<k + token.count]) == token { return k }
                k += 1
            }
            return nil
        }

        while i < chars.count {
            let c = chars[i]
            // Inline code.
            if c == "`", let j = find(["`"], from: i + 1) {
                flush()
                result.append(NSAttributedString(string: String(chars[(i + 1)..<j]),
                                                 attributes: attrs(bold: bold, italic: italic, code: true)))
                i = j + 1; continue
            }
            // Image ![alt](path).
            if c == "!", i + 1 < chars.count, chars[i + 1] == "[",
               let close = find(["]"], from: i + 2), close + 1 < chars.count, chars[close + 1] == "(",
               let paren = find([")"], from: close + 2) {
                flush()
                let alt = String(chars[(i + 2)..<close])
                let path = String(chars[(close + 2)..<paren])
                result.append(imageAttachment(path: path, alt: alt, baseURL: baseURL))
                i = paren + 1; continue
            }
            // Link [text](url).
            if c == "[", let close = find(["]"], from: i + 1), close + 1 < chars.count, chars[close + 1] == "(",
               let paren = find([")"], from: close + 2) {
                flush()
                let text = String(chars[(i + 1)..<close])
                let url = String(chars[(close + 2)..<paren])
                var a = attrs(bold: bold, italic: italic, code: false)
                a[.foregroundColor] = theme.accent
                a[.underlineStyle] = NSUnderlineStyle.single.rawValue
                if let u = URL(string: url) { a[.link] = u } else { a[.link] = url }
                result.append(NSAttributedString(string: text, attributes: a))
                i = paren + 1; continue
            }
            // Bold (** or __).
            if (c == "*" || c == "_"), i + 1 < chars.count, chars[i + 1] == c, let j = find([c, c], from: i + 2) {
                flush()
                result.append(inline(String(chars[(i + 2)..<j]), theme: theme, size: size, block: block,
                                     baseURL: baseURL, bold: true, italic: italic))
                i = j + 2; continue
            }
            // Italic (* or _).
            if (c == "*" || c == "_"), !(i + 1 < chars.count && chars[i + 1] == c), let j = find([c], from: i + 1) {
                flush()
                result.append(inline(String(chars[(i + 1)..<j]), theme: theme, size: size, block: block,
                                     baseURL: baseURL, bold: bold, italic: true))
                i = j + 1; continue
            }
            // Strikethrough.
            if c == "~", i + 1 < chars.count, chars[i + 1] == "~", let j = find(["~", "~"], from: i + 2) {
                flush()
                var a = attrs(bold: bold, italic: italic, code: false)
                a[Key.strike] = true
                a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(NSAttributedString(string: String(chars[(i + 2)..<j]), attributes: a))
                i = j + 2; continue
            }
            run.append(c); i += 1
        }
        flush()
        return result
    }

    static func imageAttachment(path: String, alt: String, baseURL: URL?) -> NSAttributedString {
        let att = NSTextAttachment()
        if let url = resolve(path, baseURL: baseURL), let img = NSImage(contentsOf: url) {
            att.image = img
            att.bounds = scaledBounds(img.size, maxWidth: 480)
        } else {
            att.image = placeholder(alt.isEmpty ? path : alt)
            att.bounds = CGRect(x: 0, y: 0, width: 240, height: 46)
        }
        let s = NSMutableAttributedString(attachment: att)
        s.addAttributes([Key.imagePath: path, Key.imageAlt: alt],
                        range: NSRange(location: 0, length: s.length))
        return s
    }

    private static func scaledBounds(_ size: NSSize, maxWidth: CGFloat) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 240, height: 160) }
        if size.width <= maxWidth { return CGRect(origin: .zero, size: size) }
        let k = maxWidth / size.width
        return CGRect(x: 0, y: 0, width: maxWidth, height: size.height * k)
    }

    private static func placeholder(_ label: String) -> NSImage {
        let size = NSSize(width: 240, height: 46)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.secondaryLabelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 6, yRadius: 6).fill()
        let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byTruncatingMiddle
        ("🖼 " + label as NSString).draw(in: NSRect(x: 8, y: 14, width: size.width - 16, height: 20),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                             .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: p])
        img.unlockFocus()
        return img
    }

    private static func resolve(_ path: String, baseURL: URL?) -> URL? {
        let t = path.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return nil }
        if t.hasPrefix("file://") { return URL(string: t) }
        if t.hasPrefix("/") { return URL(fileURLWithPath: t) }
        guard let base = baseURL else { return nil }
        return base.appendingPathComponent(t).standardizedFileURL
    }

    // MARK: Serialize — attributed string → Markdown

    static func serialize(_ attr: NSAttributedString) -> String {
        // Collect paragraphs as (block, lang, indent, number, inlineMarkdown).
        struct Para { let block: BlockKind; let lang: String; let indent: Int; let number: Int?; let text: String }
        var paras: [Para] = []
        let ns = attr.string as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { _, range, _, _ in
            let blockRaw = attr.attribute(Key.block, at: range.location, effectiveRange: nil) as? String
            let block = BlockKind.decode(blockRaw)
            let lang = (attr.attribute(Key.lang, at: range.location, effectiveRange: nil) as? String) ?? ""
            let indent = (attr.attribute(Key.indent, at: range.location, effectiveRange: nil) as? Int) ?? 0
            let number = attr.attribute(Key.number, at: range.location, effectiveRange: nil) as? Int
            let sub = attr.attributedSubstring(from: range)
            let text = (block == .code || block == .raw) ? sub.string : inlineMarkdown(sub)
            paras.append(Para(block: block, lang: lang, indent: indent, number: number, text: text))
        }

        var lines: [String] = []
        var idx = 0
        var orderedCount = 0
        while idx < paras.count {
            let p = paras[idx]
            switch p.block {
            case .code:
                lines.append("```" + (p.lang.isEmpty ? "" : p.lang))
                var j = idx
                while j < paras.count, paras[j].block == .code { lines.append(paras[j].text); j += 1 }
                lines.append("```")
                idx = j; orderedCount = 0; continue
            case .raw:
                lines.append(p.text)
            case .heading(let n):
                lines.append(String(repeating: "#", count: min(max(n, 1), 6)) + " " + p.text)
            case .quote:
                lines.append("> " + p.text)
            case .rule:
                lines.append("---")
            case .bullet:
                lines.append(String(repeating: "  ", count: p.indent) + "- " + p.text)
            case .ordered:
                orderedCount += 1
                // Respect the explicit number when set; otherwise number in order.
                let n = p.number ?? orderedCount
                lines.append(String(repeating: "  ", count: p.indent) + "\(n). " + p.text)
            case .paragraph:
                lines.append(p.text)
            }
            if case .ordered = p.block {} else { orderedCount = 0 }
            idx += 1
        }
        return lines.joined(separator: "\n")
    }

    static func inlineMarkdown(_ a: NSAttributedString) -> String {
        var out = ""
        let full = NSRange(location: 0, length: a.length)
        a.enumerateAttributes(in: full, options: []) { at, range, _ in
            if at[.attachment] != nil {
                if let table = at[Key.tableSource] as? String {   // a rendered table → its exact source
                    out += table
                    return
                }
                let path = (at[Key.imagePath] as? String) ?? ""
                let alt = (at[Key.imageAlt] as? String) ?? ""
                out += "![\(alt)](\(path))"
                return
            }
            let text = (a.string as NSString).substring(with: range)
            if text.isEmpty { return }
            let bold = (at[Key.bold] as? Bool) ?? false
            let italic = (at[Key.italic] as? Bool) ?? false
            let strike = (at[Key.strike] as? Bool) ?? false
            let code = (at[Key.code] as? Bool) ?? false

            var inner: String
            if code {
                inner = "`\(text)`"
            } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
                inner = text   // don't wrap pure whitespace in markers
            } else {
                inner = text
                if italic { inner = "*\(inner)*" }
                if bold { inner = "**\(inner)**" }
                if strike { inner = "~~\(inner)~~" }
            }
            if let link = at[.link] {
                let url = (link as? URL)?.absoluteString ?? "\(link)"
                out += "[\(inner)](\(url))"
            } else {
                out += inner
            }
        }
        return out
    }

    // MARK: Line classifiers

    private static func heading(_ t: String) -> (Int, String)? {
        guard t.hasPrefix("#") else { return nil }
        var n = 0
        for ch in t { if ch == "#" { n += 1 } else { break } }
        guard n >= 1, n <= 6, t.count > n, Array(t)[n] == " " else { return nil }
        return (n, String(t.dropFirst(n)).trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ t: String) -> Bool {
        let s = t.replacingOccurrences(of: " ", with: "")
        guard s.count >= 3 else { return false }
        return s.allSatisfy { $0 == "-" } || s.allSatisfy { $0 == "*" } || s.allSatisfy { $0 == "_" }
    }

    private static func stripQuote(_ t: String) -> String? {
        guard t.hasPrefix(">") else { return nil }
        var q = t.dropFirst()
        if q.first == " " { q = q.dropFirst() }
        return String(q)
    }

    private static func listItem(_ line: String) -> (ordered: Bool, depth: Int, number: Int, text: String)? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let depth = leading.reduce(0) { $0 + ($1 == "\t" ? 1 : 0) } + leading.filter { $0 == " " }.count / 2
        let body = line[line.index(line.startIndex, offsetBy: leading.count)...]
        if let f = body.first, f == "-" || f == "*" || f == "+",
           body.count > 1, body[body.index(after: body.startIndex)] == " " {
            return (false, depth, 0, String(body.dropFirst(2)))
        }
        var digits = ""
        for ch in body { if ch.isNumber { digits.append(ch) } else { break } }
        if !digits.isEmpty {
            let after = body.dropFirst(digits.count)
            if let sep = after.first, sep == "." || sep == ")", after.count > 1,
               after[after.index(after.startIndex, offsetBy: 1)] == " " {
                return (true, depth, Int(digits) ?? 1, String(after.dropFirst(2)))
            }
        }
        return nil
    }

    private static func isTableRow(_ t: String) -> Bool {
        t.hasPrefix("|") && t.dropFirst().contains("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("|"), t.contains("-") else { return false }
        return t.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }
}
