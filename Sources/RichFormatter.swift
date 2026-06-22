import AppKit

/// Applies formatting to the WYSIWYG editor by editing semantic attributes
/// (bold/italic flags, block kind) rather than inserting Markdown symbols. The
/// visible font is recomputed from those attributes so appearance always
/// follows meaning.
enum RichFormatter {
    typealias K = RichMarkdown.Key
    typealias Block = RichMarkdown.BlockKind

    static func apply(_ action: FormatAction, to tv: RichTextView, theme: WriterTheme, size: CGFloat) {
        switch action {
        case .bold:           toggleInline(.bold, tv, theme, size)
        case .italic:         toggleInline(.italic, tv, theme, size)
        case .strikethrough:  toggleInline(.strike, tv, theme, size)
        case .code:           toggleInline(.code, tv, theme, size)
        case .heading(let n): setBlock(.heading(n), tv, theme, size)
        case .bulletList:     setBlock(.bullet, tv, theme, size)
        case .numberList:     setBlock(.ordered, tv, theme, size)
        case .quote:          setBlock(.quote, tv, theme, size)
        case .codeBlock:      setBlock(.code, tv, theme, size)
        case .horizontalRule: insertRule(tv, theme, size)
        case .table:          insertTable(tv, theme, size)
        case .link:           insertLink(tv, theme, size)
        }
    }

    enum Inline { case bold, italic, strike, code
        var key: NSAttributedString.Key {
            switch self { case .bold: return K.bold; case .italic: return K.italic
            case .strike: return K.strike; case .code: return K.code }
        }
    }

    // MARK: Inline emphasis

    static func toggleInline(_ inl: Inline, _ tv: RichTextView, _ theme: WriterTheme, _ size: CGFloat) {
        guard let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()

        if sel.length == 0 {
            // No selection — flip the typing attribute for whatever is typed next.
            var ta = tv.typingAttributes
            let on = !((ta[inl.key] as? Bool) ?? false)
            ta[inl.key] = on ? true : nil
            let block = blockAt(storage, sel.location)
            ta[.font] = RichMarkdown.font(block: block,
                bold: flag(ta, K.bold), italic: flag(ta, K.italic), code: flag(ta, K.code), size: size)
            tv.typingAttributes = ta
            return
        }

        var allOn = true
        storage.enumerateAttribute(inl.key, in: sel, options: []) { v, _, _ in
            if ((v as? Bool) ?? false) == false { allOn = false }
        }
        let newOn = !allOn
        guard tv.shouldChangeText(in: sel, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: sel, options: []) { attrs, range, _ in
            if attrs[.attachment] != nil { return }
            var bold = flag(attrs, K.bold), italic = flag(attrs, K.italic)
            var code = flag(attrs, K.code), strike = flag(attrs, K.strike)
            switch inl {
            case .bold: bold = newOn
            case .italic: italic = newOn
            case .strike: strike = newOn
            case .code: code = newOn
            }
            let block = RichMarkdown.BlockKind.decode(attrs[K.block] as? String)
            set(storage, K.bold, bold, range); set(storage, K.italic, italic, range)
            set(storage, K.code, code, range); set(storage, K.strike, strike, range)
            storage.addAttribute(.font,
                value: RichMarkdown.font(block: block, bold: bold, italic: italic, code: code, size: size),
                range: range)
            if code { storage.addAttribute(.backgroundColor, value: theme.codeBackground, range: range) }
            else { storage.removeAttribute(.backgroundColor, range: range) }
            if strike {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else { storage.removeAttribute(.strikethroughStyle, range: range) }
        }
        storage.endEditing()
        tv.didChangeText()
    }

    // MARK: Block kind

    static func setBlock(_ requested: Block, _ tv: RichTextView, _ theme: WriterTheme, _ size: CGFloat) {
        guard let storage = tv.textStorage else { return }
        let ns = storage.string as NSString
        let paras = ns.paragraphRange(for: tv.selectedRange())
        guard tv.shouldChangeText(in: paras, replacementString: nil) else { return }
        storage.beginEditing()
        var olNum = startOrderedNumber(storage, ns, before: paras.location)
        ns.enumerateSubstrings(in: paras, options: .byParagraphs) { _, range, _, _ in
            // Toggle off → back to paragraph when the block already matches.
            let current = RichMarkdown.BlockKind.decode(storage.attribute(K.block, at: range.location, effectiveRange: nil) as? String)
            let block = (current == requested) ? .paragraph : requested
            restyle(storage, paragraph: range, block: block, theme: theme, size: size)
            if block == .ordered {
                storage.addAttribute(K.number, value: olNum, range: ns.paragraphRange(for: range))
                olNum += 1
            }
        }
        storage.endEditing()
        tv.didChangeText()
    }

    /// Where a new ordered run should start: one past the item above, else 1.
    private static func startOrderedNumber(_ storage: NSTextStorage, _ ns: NSString, before loc: Int) -> Int {
        guard loc > 0 else { return 1 }
        let prev = ns.paragraphRange(for: NSRange(location: loc - 1, length: 0))
        guard blockAt(storage, prev.location) == .ordered else { return 1 }
        return ((storage.attribute(K.number, at: prev.location, effectiveRange: nil) as? Int) ?? 0) + 1
    }

    /// Re-apply a block's styling to a paragraph, preserving inline emphasis.
    static func restyle(_ storage: NSTextStorage, paragraph range: NSRange, block: Block,
                        indent: Int = 0, theme: WriterTheme, size: CGFloat) {
        let ns = storage.string as NSString
        let full = ns.paragraphRange(for: range)
        storage.addAttribute(K.block, value: block.encoded, range: full)
        storage.addAttribute(K.indent, value: indent, range: full)
        // The ordered number only belongs on ordered items; drop it elsewhere
        // (but leave it untouched when restyling an item that's still ordered).
        if block != .ordered { storage.removeAttribute(K.number, range: full) }
        storage.addAttribute(.paragraphStyle,
            value: RichMarkdown.paragraphStyle(block, indent: indent, size: size), range: full)
        let color = RichMarkdown.blockColor(block, theme: theme)
        storage.enumerateAttributes(in: full, options: []) { attrs, r, _ in
            if attrs[.attachment] != nil { return }
            let bold = flag(attrs, K.bold), italic = flag(attrs, K.italic), code = flag(attrs, K.code)
            storage.addAttribute(.font,
                value: RichMarkdown.font(block: block, bold: bold, italic: italic, code: code, size: size), range: r)
            // Links keep the accent; code keeps its tint.
            storage.addAttribute(.foregroundColor, value: attrs[.link] != nil ? theme.accent : color, range: r)
            if code { storage.addAttribute(.backgroundColor, value: theme.codeBackground, range: r) }
        }
    }

    /// Re-derive fonts/colours for the whole document from its semantic
    /// attributes — used when the theme or text size changes (keeps the cursor).
    static func restyleAll(_ storage: NSTextStorage, theme: WriterTheme, size: CGFloat) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }
        storage.beginEditing()
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { _, range, _, _ in
            let block = blockAt(storage, range.location)
            let indent = (storage.attribute(K.indent, at: range.location, effectiveRange: nil) as? Int) ?? 0
            restyle(storage, paragraph: range, block: block, indent: indent, theme: theme, size: size)
        }
        storage.endEditing()
    }

    // MARK: Inserts

    static func insertRule(_ tv: RichTextView, _ theme: WriterTheme, _ size: CGFloat) {
        insertParagraph(tv, text: "—", block: .rule, theme: theme, size: size)
    }

    static func insertTable(_ tv: RichTextView, _ theme: WriterTheme, _ size: CGFloat) {
        let rows = ["| Column 1 | Column 2 |", "|----------|----------|", "| Cell     | Cell     |"]
        for row in rows { insertParagraph(tv, text: row, block: .raw, theme: theme, size: size) }
    }

    private static func insertParagraph(_ tv: RichTextView, text: String, block: Block,
                                        theme: WriterTheme, size: CGFloat) {
        guard let storage = tv.textStorage else { return }
        let para = NSMutableAttributedString(string: text + "\n", attributes: [
            K.block: block.encoded,
            .font: RichMarkdown.font(block: block, bold: false, italic: false, code: false, size: size),
            .foregroundColor: RichMarkdown.blockColor(block, theme: theme),
            .paragraphStyle: RichMarkdown.paragraphStyle(block, indent: 0, size: size),
        ])
        let ns = storage.string as NSString
        var at = tv.selectedRange().location
        // Start the block on a fresh line.
        let prefix = (at > 0 && ns.character(at: at - 1) != 10) ? "\n" : ""
        let insert = NSMutableAttributedString(string: prefix)
        insert.append(para)
        guard tv.shouldChangeText(in: NSRange(location: at, length: 0), replacementString: insert.string) else { return }
        storage.replaceCharacters(in: NSRange(location: at, length: 0), with: insert)
        tv.didChangeText()
        at += insert.length
        tv.setSelectedRange(NSRange(location: at, length: 0))
    }

    static func insertLink(_ tv: RichTextView, _ theme: WriterTheme, _ size: CGFloat) {
        guard let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()
        let ns = storage.string as NSString
        let label = sel.length > 0 ? ns.substring(with: sel) : "link"
        let block = blockAt(storage, sel.location)
        var attrs: [NSAttributedString.Key: Any] = [
            K.block: block.encoded,
            .font: RichMarkdown.font(block: block, bold: false, italic: false, code: false, size: size),
            .foregroundColor: theme.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .link: URL(string: "https://") as Any,
        ]
        attrs[.paragraphStyle] = RichMarkdown.paragraphStyle(block, indent: 0, size: size)
        let link = NSAttributedString(string: label, attributes: attrs)
        guard tv.shouldChangeText(in: sel, replacementString: label) else { return }
        storage.replaceCharacters(in: sel, with: link)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: sel.location, length: (label as NSString).length))
    }

    // MARK: Newline continuation (called after Return)

    static func handleNewline(_ tv: RichTextView, _ theme: WriterTheme, _ size: CGFloat) {
        guard let storage = tv.textStorage else { return }
        let ns = storage.string as NSString
        let caret = tv.selectedRange().location
        let curPara = ns.paragraphRange(for: NSRange(location: min(caret, ns.length), length: 0))
        guard curPara.location > 0 else { return }
        let prevPara = ns.paragraphRange(for: NSRange(location: curPara.location - 1, length: 0))
        let prevBlock = blockAt(storage, prevPara.location)
        let prevText = ns.substring(with: prevPara).trimmingCharacters(in: .whitespacesAndNewlines)

        var newBlock: Block = .paragraph
        switch prevBlock {
        case .heading, .rule:
            newBlock = .paragraph
        case .bullet, .ordered, .quote, .code:
            if prevText.isEmpty {
                restyle(storage, paragraph: prevPara, block: .paragraph, theme: theme, size: size) // exit list/quote
                newBlock = .paragraph
            } else {
                newBlock = prevBlock
            }
        default:
            newBlock = .paragraph
        }
        // Continuing a list inherits its depth; the ordered number steps by one.
        let prevIndent = (storage.attribute(K.indent, at: prevPara.location, effectiveRange: nil) as? Int) ?? 0
        let newIndent = (newBlock == .bullet || newBlock == .ordered) ? prevIndent : 0
        let target = ns.paragraphRange(for: NSRange(location: min(tv.selectedRange().location, ns.length), length: 0))
        restyle(storage, paragraph: target, block: newBlock, indent: newIndent, theme: theme, size: size)

        var nextNumber: Int? = nil
        if newBlock == .ordered {
            let prevNum = (storage.attribute(K.number, at: prevPara.location, effectiveRange: nil) as? Int) ?? 0
            nextNumber = prevNum + 1
            storage.addAttribute(K.number, value: prevNum + 1, range: ns.paragraphRange(for: target))
        }

        // Make sure typing continues in the right style.
        var ta = tv.typingAttributes
        ta[K.block] = newBlock.encoded
        ta[K.indent] = newIndent
        ta[K.bold] = nil; ta[K.italic] = nil; ta[K.code] = nil; ta[K.strike] = nil
        if let nextNumber { ta[K.number] = nextNumber } else { ta[K.number] = nil }
        ta[.font] = RichMarkdown.font(block: newBlock, bold: false, italic: false, code: false, size: size)
        ta[.foregroundColor] = RichMarkdown.blockColor(newBlock, theme: theme)
        ta[.paragraphStyle] = RichMarkdown.paragraphStyle(newBlock, indent: newIndent, size: size)
        tv.typingAttributes = ta
    }

    // MARK: Helpers

    static func blockAt(_ storage: NSTextStorage, _ loc: Int) -> Block {
        guard storage.length > 0 else { return .paragraph }
        let i = min(max(loc, 0), storage.length - 1)
        return RichMarkdown.BlockKind.decode(storage.attribute(K.block, at: i, effectiveRange: nil) as? String)
    }

    private static func flag(_ attrs: [NSAttributedString.Key: Any], _ key: NSAttributedString.Key) -> Bool {
        (attrs[key] as? Bool) ?? false
    }

    private static func set(_ storage: NSTextStorage, _ key: NSAttributedString.Key, _ on: Bool, _ range: NSRange) {
        if on { storage.addAttribute(key, value: true, range: range) }
        else { storage.removeAttribute(key, range: range) }
    }
}
