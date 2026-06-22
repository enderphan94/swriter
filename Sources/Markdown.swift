import AppKit

/// Renders Markdown to a finished `NSAttributedString` with book typography —
/// serif body, real headings, quotes, lists, fenced code, and proper
/// `NSTextTable` tables. Used by both Reading mode and the A5 PDF export.
///
/// It's a small, line-oriented renderer (no dependencies) covering the Markdown
/// people actually write for notes and books.
enum MarkdownRenderer {

    /// - forPrint: justify and hyphenate body text for a printed page; left-align
    ///   for comfortable on-screen reading.
    /// - baseURL: the note's folder, so relative image paths resolve.
    static func attributed(_ markdown: String, theme: WriterTheme,
                           bodySize: CGFloat, forPrint: Bool,
                           baseURL: URL? = nil) -> NSAttributedString {
        Builder(theme: theme, size: bodySize, forPrint: forPrint, baseURL: baseURL).build(markdown)
    }

    // MARK: - Builder

    private final class Builder {
        let theme: WriterTheme
        let size: CGFloat
        let forPrint: Bool
        let baseURL: URL?
        let ink: NSColor
        let out = NSMutableAttributedString()

        init(theme: WriterTheme, size: CGFloat, forPrint: Bool, baseURL: URL?) {
            self.theme = theme; self.size = size; self.forPrint = forPrint; self.baseURL = baseURL
            self.ink = forPrint ? NSColor.black : theme.text
        }

        func build(_ markdown: String) -> NSAttributedString {
            let lines = markdown.components(separatedBy: "\n")
            var i = 0
            while i < lines.count {
                let line = lines[i]
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Blank line → vertical space, so the paragraph breaks people
                // make in the visual editor show up on the book page too.
                if trimmed.isEmpty { appendBlankLine(); i += 1; continue }

                // Fenced code block.
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    let fence = String(trimmed.prefix(3))
                    var body: [String] = []
                    i += 1
                    while i < lines.count,
                          !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        body.append(lines[i]); i += 1
                    }
                    i += 1 // closing fence
                    appendCodeBlock(body.joined(separator: "\n"))
                    continue
                }

                // Heading.
                if let (level, text) = heading(trimmed) {
                    appendHeading(text, level: level)
                    i += 1; continue
                }

                // Horizontal rule.
                if isRule(trimmed) { appendRule(); i += 1; continue }

                // Image on its own line.
                if let img = imageOnly(trimmed) {
                    appendImage(path: img.path, alt: img.alt); i += 1; continue
                }

                // Table: header row + separator row.
                if trimmed.contains("|"), i + 1 < lines.count,
                   isTableSeparator(lines[i + 1]) {
                    var rows: [String] = [line]
                    i += 1
                    rows.append(lines[i]) // separator
                    i += 1
                    while i < lines.count, lines[i].contains("|"),
                          !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        rows.append(lines[i]); i += 1
                    }
                    appendTable(rows)
                    continue
                }

                // Blockquote (consecutive `>` lines).
                if trimmed.hasPrefix(">") {
                    var quote: [String] = []
                    while i < lines.count,
                          lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                        var q = lines[i].trimmingCharacters(in: .whitespaces)
                        q.removeFirst()
                        if q.hasPrefix(" ") { q.removeFirst() }
                        quote.append(q); i += 1
                    }
                    appendQuote(quote.joined(separator: " "))
                    continue
                }

                // List (consecutive item lines).
                if listMarker(line) != nil {
                    while i < lines.count, let m = listMarker(lines[i]) {
                        appendListItem(m, line: lines[i])
                        i += 1
                    }
                    continue
                }

                // Paragraph — one line per paragraph, matching the visual editor
                // (one Enter = one paragraph) so Write and Read look the same.
                appendParagraph(line)
                i += 1
            }
            return out
        }

        // MARK: Block emitters

        private func appendHeading(_ text: String, level: Int) {
            let scale: CGFloat = [1.9, 1.55, 1.3, 1.15, 1.05, 1.0][min(level - 1, 5)]
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = size * (level <= 2 ? 1.3 : 0.9)
            p.paragraphSpacing = size * 0.4
            p.lineHeightMultiple = 1.1
            let attr = inline(text, base: [
                .font: Typeface.serif(size * scale, weight: .bold),
                .foregroundColor: ink,
                .paragraphStyle: p,
            ], bold: true)
            out.append(attr)
            out.append(NSAttributedString(string: "\n"))
        }

        private func appendParagraph(_ text: String) {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.5
            p.paragraphSpacing = size * 0.85
            p.alignment = forPrint ? .justified : .natural
            if forPrint { p.hyphenationFactor = 0.9 }
            out.append(inline(text, base: bodyAttrs(p)))
            out.append(NSAttributedString(string: "\n"))
        }

        /// An empty line — one per blank line in the source — so extra Returns
        /// add real vertical space on the page.
        private func appendBlankLine() {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.4
            out.append(NSAttributedString(string: "\n", attributes: [.font: Typeface.serif(size), .paragraphStyle: p]))
        }

        private func appendQuote(_ text: String) {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.45
            p.paragraphSpacing = size * 0.85
            p.firstLineHeadIndent = size * 1.4
            p.headIndent = size * 1.4
            p.tailIndent = -size * 0.6
            let attr = inline(text, base: [
                .font: Typeface.serifItalic(size),
                .foregroundColor: forPrint ? NSColor.darkGray : theme.text.withAlphaComponent(0.8),
                .paragraphStyle: p,
            ], italic: true)
            out.append(attr)
            out.append(NSAttributedString(string: "\n"))
        }

        private func appendListItem(_ marker: ListMark, line: String) {
            let indent = size * (1.6 + CGFloat(marker.level) * 1.4)
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.45
            p.paragraphSpacing = size * 0.25
            p.firstLineHeadIndent = indent - size
            p.headIndent = indent
            p.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
            let bullet = marker.ordered ? "\(marker.number).\t" : "•\t"
            let head = NSMutableAttributedString(string: bullet, attributes: bodyAttrs(p))
            head.append(inline(marker.text, base: bodyAttrs(p)))
            out.append(head)
            out.append(NSAttributedString(string: "\n"))
        }

        private func appendCodeBlock(_ code: String) {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.25
            p.paragraphSpacing = size * 0.85
            p.firstLineHeadIndent = size
            p.headIndent = size
            out.append(NSAttributedString(string: code + "\n", attributes: [
                .font: Typeface.mono(size * 0.92),
                .foregroundColor: ink,
                .backgroundColor: forPrint ? NSColor(white: 0.94, alpha: 1) : theme.codeBackground,
                .paragraphStyle: p,
            ]))
        }

        private func appendRule() {
            let p = NSMutableParagraphStyle()
            p.alignment = .center
            p.paragraphSpacingBefore = size
            p.paragraphSpacing = size
            out.append(NSAttributedString(string: "* * *\n", attributes: [
                .font: Typeface.serif(size),
                .foregroundColor: forPrint ? NSColor.gray : theme.faint,
                .paragraphStyle: p,
            ]))
        }

        private func appendImage(path: String, alt: String) {
            out.append(imageString(path: path, alt: alt, block: true))
            out.append(NSAttributedString(string: "\n"))
        }

        /// Build a centered image attachment (or a captioned placeholder when the
        /// file can't be loaded). Local relative paths resolve against `baseURL`.
        private func imageString(path: String, alt: String, block: Bool) -> NSAttributedString {
            if let url = resolveImage(path), let img = NSImage(contentsOf: url) {
                let att = NSTextAttachment()
                att.image = img
                var s = img.size
                let maxW: CGFloat = forPrint ? 300 : 600
                if s.width > maxW, s.width > 0 { let k = maxW / s.width; s = NSSize(width: maxW, height: s.height * k) }
                if s.width <= 0 || s.height <= 0 { s = NSSize(width: 220, height: 140) }
                att.bounds = CGRect(origin: .zero, size: s)
                let a = NSMutableAttributedString(attachment: att)
                if block {
                    let p = NSMutableParagraphStyle()
                    p.alignment = .center
                    p.paragraphSpacingBefore = size * 0.5
                    p.paragraphSpacing = size * 0.7
                    a.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: a.length))
                }
                return a
            }
            // Couldn't load it — show a labeled placeholder so nothing is lost.
            var attrs: [NSAttributedString.Key: Any] = [
                .font: Typeface.serifItalic(size),
                .foregroundColor: forPrint ? NSColor.gray : theme.faint,
            ]
            if block {
                let p = NSMutableParagraphStyle(); p.alignment = .center
                p.paragraphSpacing = size * 0.6; attrs[.paragraphStyle] = p
            }
            return NSAttributedString(string: "🖼 " + (alt.isEmpty ? path : alt), attributes: attrs)
        }

        /// Resolve a local image reference; remote URLs are skipped (no network).
        private func resolveImage(_ path: String) -> URL? {
            let t = path.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("http://") || t.hasPrefix("https://") { return nil }
            if t.hasPrefix("file://") { return URL(string: t) }
            if t.hasPrefix("/") { return URL(fileURLWithPath: t) }
            guard let base = baseURL else { return nil }
            // appendingPathComponent + standardize resolves "../" and is robust
            // whether or not `base` carries a trailing slash.
            return base.appendingPathComponent(t).standardizedFileURL
        }

        /// A line that is *only* an image: `![alt](path)`.
        private func imageOnly(_ t: String) -> (alt: String, path: String)? {
            guard t.hasPrefix("!["), t.hasSuffix(")"), let mid = t.range(of: "](") else { return nil }
            let alt = String(t[t.index(t.startIndex, offsetBy: 2)..<mid.lowerBound])
            let path = String(t[mid.upperBound..<t.index(before: t.endIndex)])
            return path.isEmpty || alt.contains("](") ? nil : (alt, path)
        }

        private func appendTable(_ rows: [String]) {
            let cells = rows.enumerated()
                .filter { $0.offset != 1 }              // drop the |---| separator
                .map { tableCells($0.element) }
            guard let first = cells.first else { return }
            let cols = first.count
            let table = NSTextTable()
            table.numberOfColumns = cols
            table.collapsesBorders = true

            for (r, row) in cells.enumerated() {
                for c in 0..<cols {
                    let block = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1,
                                                 startingColumn: c, columnSpan: 1)
                    block.setBorderColor(forPrint ? NSColor.gray : theme.faint)
                    block.setWidth(0.5, type: .absoluteValueType, for: .border)
                    block.setWidth(6, type: .absoluteValueType, for: .padding)
                    let p = NSMutableParagraphStyle()
                    p.textBlocks = [block]
                    p.alignment = .left
                    let text = c < row.count ? row[c] : ""
                    let font = r == 0 ? Typeface.serif(size * 0.95, weight: .bold)
                                      : Typeface.serif(size * 0.95)
                    let cell = NSMutableAttributedString(
                        string: "", attributes: [.paragraphStyle: p, .font: font, .foregroundColor: ink])
                    cell.append(inline(text, base: [.font: font, .foregroundColor: ink, .paragraphStyle: p],
                                       bold: r == 0))
                    cell.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: p]))
                    out.append(cell)
                }
            }
            // Trailing spacer so the next block clears the table.
            out.append(NSAttributedString(string: "\n", attributes: [.font: Typeface.serif(size * 0.4)]))
        }

        private func bodyAttrs(_ p: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
            [.font: Typeface.serif(size), .foregroundColor: ink, .paragraphStyle: p]
        }

        // MARK: Inline scanner — **bold**, *italic*, `code`, ~~strike~~, [text](url)

        private func inline(_ s: String, base: [NSAttributedString.Key: Any],
                            bold: Bool = false, italic: Bool = false) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let chars = Array(s)
            var i = 0
            var run = ""

            func flushRun() {
                guard !run.isEmpty else { return }
                result.append(NSAttributedString(string: run, attributes: styled(base, bold: bold, italic: italic)))
                run = ""
            }

            func find(_ token: [Character], from: Int) -> Int? {
                guard token.count > 0, from <= chars.count - token.count else { return nil }
                var k = from
                while k <= chars.count - token.count {
                    if Array(chars[k..<k+token.count]) == token { return k }
                    k += 1
                }
                return nil
            }

            while i < chars.count {
                let c = chars[i]

                // Inline code.
                if c == "`", let j = find(["`"], from: i + 1) {
                    flushRun()
                    let content = String(chars[(i+1)..<j])
                    var codeAttrs = base
                    codeAttrs[.font] = Typeface.mono(size * 0.92)
                    codeAttrs[.backgroundColor] = forPrint ? NSColor(white: 0.94, alpha: 1) : theme.codeBackground
                    result.append(NSAttributedString(string: content, attributes: codeAttrs))
                    i = j + 1; continue
                }

                // Bold (** or __).
                if (c == "*" || c == "_"), i + 1 < chars.count, chars[i+1] == c,
                   let j = find([c, c], from: i + 2) {
                    flushRun()
                    let content = String(chars[(i+2)..<j])
                    result.append(inline(content, base: base, bold: true, italic: italic))
                    i = j + 2; continue
                }

                // Italic (* or _).
                if (c == "*" || c == "_"), let j = find([c], from: i + 1),
                   !(i + 1 < chars.count && chars[i+1] == c) {
                    flushRun()
                    let content = String(chars[(i+1)..<j])
                    result.append(inline(content, base: base, bold: bold, italic: true))
                    i = j + 1; continue
                }

                // Strikethrough.
                if c == "~", i + 1 < chars.count, chars[i+1] == "~", let j = find(["~", "~"], from: i + 2) {
                    flushRun()
                    let content = String(chars[(i+2)..<j])
                    var sAttrs = styled(base, bold: bold, italic: italic)
                    sAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    result.append(NSAttributedString(string: content, attributes: sAttrs))
                    i = j + 2; continue
                }

                // Inline image ![alt](path).
                if c == "!", i + 1 < chars.count, chars[i + 1] == "[",
                   let close = find(["]"], from: i + 2), close + 1 < chars.count, chars[close + 1] == "(",
                   let paren = find([")"], from: close + 2) {
                    flushRun()
                    let alt = String(chars[(i + 2)..<close])
                    let path = String(chars[(close + 2)..<paren])
                    result.append(imageString(path: path, alt: alt, block: false))
                    i = paren + 1; continue
                }

                // Link [text](url).
                if c == "[", let close = find(["]"], from: i + 1),
                   close + 1 < chars.count, chars[close+1] == "(",
                   let paren = find([")"], from: close + 2) {
                    flushRun()
                    let label = String(chars[(i+1)..<close])
                    let url = String(chars[(close+2)..<paren])
                    var linkAttrs = styled(base, bold: bold, italic: italic)
                    linkAttrs[.foregroundColor] = forPrint ? NSColor(srgb: 0x1A4FB4) : theme.accent
                    linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    if let u = URL(string: url) { linkAttrs[.link] = u }
                    result.append(NSAttributedString(string: label, attributes: linkAttrs))
                    i = paren + 1; continue
                }

                run.append(c); i += 1
            }
            flushRun()
            return result
        }

        private func styled(_ base: [NSAttributedString.Key: Any], bold: Bool, italic: Bool)
            -> [NSAttributedString.Key: Any] {
            guard bold || italic else { return base }
            var attrs = base
            let f = (base[.font] as? NSFont) ?? Typeface.serif(size)
            attrs[.font] = restyle(f, bold: bold, italic: italic)
            return attrs
        }

        private func restyle(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
            var traits: NSFontDescriptor.SymbolicTraits = []
            if bold { traits.insert(.bold) }
            if italic { traits.insert(.italic) }
            let d = font.fontDescriptor.withSymbolicTraits(traits)
            return NSFont(descriptor: d, size: font.pointSize) ?? font
        }

        // MARK: Line classifiers

        private func heading(_ t: String) -> (Int, String)? {
            guard t.hasPrefix("#") else { return nil }
            var n = 0
            for ch in t { if ch == "#" { n += 1 } else { break } }
            guard n >= 1, n <= 6, t.count > n, Array(t)[n] == " " else { return nil }
            let text = String(t.dropFirst(n)).trimmingCharacters(in: .whitespaces)
            return (n, text)
        }

        private func isRule(_ t: String) -> Bool {
            let stripped = t.replacingOccurrences(of: " ", with: "")
            guard stripped.count >= 3 else { return false }
            return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" }
                || stripped.allSatisfy { $0 == "_" }
        }

        private func isTableSeparator(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.contains("|"), t.contains("-") else { return false }
            return t.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
        }

        private func tableCells(_ line: String) -> [String] {
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        private struct ListMark { let ordered: Bool; let number: Int; let text: String; let level: Int }

        private func listMarker(_ line: String) -> ListMark? {
            let leading = line.prefix { $0 == " " || $0 == "\t" }
            let level = leading.reduce(0) { $0 + ($1 == "\t" ? 1 : 0) } + leading.filter { $0 == " " }.count / 2
            let body = line[line.index(line.startIndex, offsetBy: leading.count)...]
            // Unordered.
            if let f = body.first, f == "-" || f == "*" || f == "+",
               body.count > 1, body[body.index(after: body.startIndex)] == " " {
                return ListMark(ordered: false, number: 0,
                                text: String(body.dropFirst(2)), level: level)
            }
            // Ordered: 1.  / 12)
            var digits = ""
            for ch in body { if ch.isNumber { digits.append(ch) } else { break } }
            if !digits.isEmpty {
                let after = body.dropFirst(digits.count)
                if let sep = after.first, sep == "." || sep == ")",
                   after.count > 1, after[after.index(after.startIndex, offsetBy: 1)] == " " {
                    return ListMark(ordered: true, number: Int(digits) ?? 1,
                                    text: String(after.dropFirst(2)), level: level)
                }
            }
            return nil
        }
    }
}
