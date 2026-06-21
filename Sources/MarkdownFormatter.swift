import AppKit

/// What the toolbar and Format menu do. Mirrors the writing tools of a web
/// Markdown editor (bold, italic, table, …) but applied to a native text view.
enum FormatAction: Equatable {
    case bold, italic, strikethrough, code
    case heading(Int)
    case bulletList, numberList, quote
    case link, table, codeBlock, horizontalRule
}

/// Edits Markdown source in place through the text view so Undo and live
/// re-highlighting both keep working (every change goes via
/// `shouldChangeText` / `didChangeText`).
enum MarkdownFormatter {

    static func apply(_ action: FormatAction, to tv: NSTextView) {
        switch action {
        case .bold:          wrap(tv, "**", "**", placeholder: "bold text")
        case .italic:        wrap(tv, "*", "*", placeholder: "italic text")
        case .strikethrough: wrap(tv, "~~", "~~", placeholder: "struck text")
        case .code:          wrap(tv, "`", "`", placeholder: "code")
        case .heading(let n): heading(tv, level: n)
        case .bulletList:    linePrefix(tv, "- ")
        case .numberList:    numberLines(tv)
        case .quote:         linePrefix(tv, "> ")
        case .link:          link(tv)
        case .table:         insertBlock(tv, Self.tableTemplate)
        case .codeBlock:     codeBlock(tv)
        case .horizontalRule: insertBlock(tv, "---")
        }
    }

    // MARK: Inline

    private static func wrap(_ tv: NSTextView, _ left: String, _ right: String, placeholder: String) {
        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let selected = ns.substring(with: sel)
        let inner = selected.isEmpty ? placeholder : selected

        // Toggle off if the selection is already wrapped.
        if !selected.isEmpty, selected.hasPrefix(left), selected.hasSuffix(right),
           selected.count >= left.count + right.count {
            let stripped = String(selected.dropFirst(left.count).dropLast(right.count))
            replace(tv, sel, with: stripped,
                    select: NSRange(location: sel.location, length: (stripped as NSString).length))
            return
        }

        let replacement = left + inner + right
        let innerStart = sel.location + (left as NSString).length
        let select = NSRange(location: innerStart, length: (inner as NSString).length)
        replace(tv, sel, with: replacement, select: select)
    }

    // MARK: Line-level

    private static func heading(_ tv: NSTextView, level: Int) {
        transformLines(tv) { line in
            let body = stripLeadingHashes(line)
            let prefix = String(repeating: "#", count: level) + " "
            // Toggle: tapping the same level again clears it.
            if line == prefix + body { return body }
            return prefix + body
        }
    }

    private static func linePrefix(_ tv: NSTextView, _ prefix: String) {
        let lines = selectedLines(tv)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allPrefixed = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.hasPrefix(prefix) }
        transformLines(tv) { line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if allPrefixed { return String(line.dropFirst(prefix.count)) }
            return prefix + line
        }
    }

    private static func numberLines(_ tv: NSTextView) {
        var i = 0
        transformLines(tv) { line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            i += 1
            return "\(i). " + stripLeadingNumber(line)
        }
    }

    // MARK: Blocks

    private static func link(_ tv: NSTextView) {
        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let selected = ns.substring(with: sel)
        if selected.isEmpty {
            let text = "[title](https://)"
            // Put the cursor inside the URL parens.
            let select = NSRange(location: sel.location + 8, length: 8) // "https://"
            replace(tv, sel, with: text, select: select)
        } else {
            let text = "[\(selected)](https://)"
            let urlStart = sel.location + (selected as NSString).length + 3
            replace(tv, sel, with: text, select: NSRange(location: urlStart, length: 8))
        }
    }

    private static func codeBlock(_ tv: NSTextView) {
        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let selected = ns.substring(with: sel)
        let inner = selected.isEmpty ? "code" : selected
        let block = "```\n\(inner)\n```"
        let leading = needsLeadingNewline(ns, at: sel.location) ? "\n" : ""
        let full = leading + block
        let innerStart = sel.location + (leading as NSString).length + 4 // "```\n"
        replace(tv, sel, with: full, select: NSRange(location: innerStart, length: (inner as NSString).length))
    }

    /// Insert a standalone block (table, rule) on its own lines.
    private static func insertBlock(_ tv: NSTextView, _ body: String) {
        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let leading = needsLeadingNewline(ns, at: sel.location) ? "\n" : ""
        let trailing = needsTrailingNewline(ns, at: sel.location + sel.length) ? "\n" : ""
        let full = leading + body + trailing
        let caret = sel.location + (full as NSString).length
        replace(tv, sel, with: full, select: NSRange(location: caret, length: 0))
    }

    private static let tableTemplate = """
    | Column 1 | Column 2 |
    |----------|----------|
    | Cell     | Cell     |
    """

    // MARK: Mechanics

    /// Replace `range` with `string`, routing through the text view so Undo and
    /// the change notification (which drives re-highlight + autosave) both fire.
    private static func replace(_ tv: NSTextView, _ range: NSRange, with string: String, select: NSRange?) {
        guard tv.shouldChangeText(in: range, replacementString: string) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: string)
        tv.didChangeText()
        if let select { tv.setSelectedRange(select) }
    }

    /// The full lines covered by the current selection, as strings.
    private static func selectedLines(_ tv: NSTextView) -> [String] {
        let ns = tv.string as NSString
        let lineRange = ns.paragraphRange(for: tv.selectedRange())
        return ns.substring(with: lineRange).components(separatedBy: "\n")
    }

    /// Apply `transform` to each line spanned by the selection and write it back,
    /// re-selecting the rewritten block.
    private static func transformLines(_ tv: NSTextView, _ transform: (String) -> String) {
        let ns = tv.string as NSString
        let lineRange = ns.paragraphRange(for: tv.selectedRange())
        let block = ns.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() } // drop the empty piece after the last \n
        let rewritten = lines.map(transform).joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")
        replace(tv, lineRange, with: rewritten,
                select: NSRange(location: lineRange.location, length: (rewritten as NSString).length))
    }

    private static func stripLeadingHashes(_ line: String) -> String {
        var s = Substring(line)
        while s.first == "#" { s = s.dropFirst() }
        while s.first == " " { s = s.dropFirst() }
        return String(s)
    }

    private static func stripLeadingNumber(_ line: String) -> String {
        // Remove an existing "12. " / "3) " prefix so re-numbering is clean.
        guard let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }) else { return line }
        let head = line[line.startIndex..<dot]
        if !head.isEmpty, head.allSatisfy(\.isNumber) {
            var rest = line[line.index(after: dot)...]
            while rest.first == " " { rest = rest.dropFirst() }
            return String(rest)
        }
        return line
    }

    private static func needsLeadingNewline(_ ns: NSString, at loc: Int) -> Bool {
        loc > 0 && ns.character(at: loc - 1) != 10 // not already at line start
    }

    private static func needsTrailingNewline(_ ns: NSString, at loc: Int) -> Bool {
        loc < ns.length && ns.character(at: loc) != 10
    }
}

extension AppStore {
    /// Run a formatting command against the focused editor.
    func format(_ action: FormatAction) {
        guard let tv = activeTextView else { NSSound.beep(); return }
        MarkdownFormatter.apply(action, to: tv)
    }
}
