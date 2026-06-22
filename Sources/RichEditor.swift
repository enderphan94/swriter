import SwiftUI
import AppKit

/// The visual writing surface. People edit formatted text — real bold, real
/// headings, real images — and the document is kept as Markdown underneath:
/// loaded via `RichMarkdown.parse`, saved via `RichMarkdown.serialize` on every
/// edit. The Markdown source is never shown here.
struct RichEditor: NSViewRepresentable {
    let docID: String
    let markdown: String
    let theme: WriterTheme
    let fontSize: CGFloat
    let baseURL: URL?
    var onChange: (String) -> Void
    var onActivate: (NSTextView?) -> Void
    var onImageSave: (NSPasteboard) -> String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true

        // Custom text system so list bullets/numbers can be drawn in the margin.
        let storage = NSTextStorage()
        let layout = RichLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 4
        layout.addTextContainer(container)

        let tv = RichTextView(frame: .zero, textContainer: container)
        tv.isRichText = true
        tv.allowsUndo = true
        tv.allowsImageEditing = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.usesFontPanel = false
        tv.usesRuler = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 4
        tv.delegate = context.coordinator
        tv.baseURL = baseURL
        tv.imageSaver = onImageSave
        tv.onNewline = { [weak coordinator = context.coordinator] in coordinator?.newline() }
        tv.onContentChanged = { [weak coordinator = context.coordinator] in coordinator?.reserialize() }
        tv.registerForDraggedTypes(Array(Set(tv.registeredDraggedTypes + [.png, .tiff, .fileURL])))

        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.docID = docID

        load(into: tv)
        applyChrome(tv, scroll)
        onActivate(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        guard let tv = c.textView else { return }
        c.parent = self
        tv.baseURL = baseURL

        if c.docID != docID {
            c.docID = docID
            c.isProgrammatic = true
            load(into: tv)
            c.isProgrammatic = false
            applyChrome(tv, scroll)
            tv.scroll(.zero)
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        } else if c.theme != theme || c.fontSize != fontSize {
            if let storage = tv.textStorage {
                RichFormatter.restyleAll(storage, theme: theme, size: fontSize)
            }
            applyChrome(tv, scroll)
        }
        c.theme = theme; c.fontSize = fontSize
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.parent.onActivate(nil)
    }

    private func load(into tv: RichTextView) {
        let attr = RichMarkdown.parse(markdown, theme: theme, size: fontSize, baseURL: baseURL)
        tv.textStorage?.setAttributedString(attr)
        tv.typingAttributes = [
            RichMarkdown.Key.block: RichMarkdown.BlockKind.paragraph.encoded,
            .font: RichMarkdown.font(block: .paragraph, bold: false, italic: false, code: false, size: fontSize),
            .foregroundColor: theme.text,
            .paragraphStyle: RichMarkdown.paragraphStyle(.paragraph, indent: 0, size: fontSize),
        ]
    }

    private func applyChrome(_ tv: RichTextView, _ scroll: NSScrollView) {
        tv.backgroundColor = theme.background
        scroll.backgroundColor = theme.background
        tv.insertionPointColor = theme.text
        tv.selectedTextAttributes = [.backgroundColor: theme.selection]
        (tv.layoutManager as? RichLayoutManager)?.markerColor = theme.text.withAlphaComponent(0.6)
        tv.measure = 720
        tv.refreshInset()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichEditor
        weak var textView: RichTextView?
        var docID = ""
        var theme: WriterTheme = .light
        var fontSize: CGFloat = 17
        var isProgrammatic = false

        init(_ parent: RichEditor) {
            self.parent = parent
            self.theme = parent.theme
            self.fontSize = parent.fontSize
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammatic, let tv = textView, let storage = tv.textStorage else { return }
            parent.onChange(RichMarkdown.serialize(storage))
        }

        /// Called after Return: fix the new paragraph's block, then re-serialize.
        func newline() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            RichFormatter.handleNewline(tv, parent.theme, parent.fontSize)
            parent.onChange(RichMarkdown.serialize(storage))
        }

        /// Re-serialize after an attribute-only change (e.g. "Set Number…").
        func reserialize() {
            guard let storage = textView?.textStorage else { return }
            parent.onChange(RichMarkdown.serialize(storage))
        }
    }
}

/// An `NSTextView` for visual editing: centered measure, image paste, paste
/// normalization, and a Return hook for block continuation.
final class RichTextView: NSTextView {
    var measure: CGFloat = 720
    var baseURL: URL?
    var imageSaver: ((NSPasteboard) -> String?)?
    var onNewline: (() -> Void)?
    var onContentChanged: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshInset()
    }

    func refreshInset() {
        let side = max(28, (bounds.width - measure) / 2)
        let inset = NSSize(width: side, height: 44)
        if textContainerInset != inset { textContainerInset = inset }
    }

    override func insertNewline(_ sender: Any?) {
        super.insertNewline(sender)
        onNewline?()
    }

    /// Paste an image as an inline picture; otherwise paste plain text (so
    /// foreign rich formatting never leaks into the document).
    override func paste(_ sender: Any?) {
        if let saver = imageSaver, let path = saver(NSPasteboard.general) {
            insertImage(path: path, alt: "")
            return
        }
        if let s = NSPasteboard.general.string(forType: .string) {
            insertPlain(s)
            return
        }
        super.paste(sender)
    }

    func insertImage(path: String, alt: String) {
        let att = RichMarkdown.imageAttachment(path: path, alt: alt, baseURL: baseURL)
        let r = selectedRange()
        guard shouldChangeText(in: r, replacementString: "\u{FFFC}") else { return }
        textStorage?.replaceCharacters(in: r, with: att)
        didChangeText()
        setSelectedRange(NSRange(location: r.location + att.length, length: 0))
    }

    // MARK: Drag-and-drop of image files (e.g. a dragged screenshot)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        swPasteboardHasImage(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        swPasteboardHasImage(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let saver = imageSaver, swPasteboardHasImage(pb) {
            let point = convert(sender.draggingLocation, from: nil)
            let index = min(characterIndexForInsertion(at: point), textStorage?.length ?? 0)
            setSelectedRange(NSRange(location: index, length: 0))
            if let path = saver(pb) { insertImage(path: path, alt: ""); return true }
        }
        return super.performDragOperation(sender)
    }

    private func insertPlain(_ s: String) {
        let r = selectedRange()
        guard shouldChangeText(in: r, replacementString: s) else { return }
        textStorage?.replaceCharacters(in: r, with: NSAttributedString(string: s, attributes: typingAttributes))
        didChangeText()
        setSelectedRange(NSRange(location: r.location + (s as NSString).length, length: 0))
    }

    /// Add "Set Number…" to the context menu when right-clicking an ordered item.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let storage = textStorage, storage.length > 0 else { return menu }
        let point = convert(event.locationInWindow, from: nil)
        let index = min(characterIndexForInsertion(at: point), storage.length - 1)
        let block = RichMarkdown.BlockKind.decode(
            storage.attribute(RichMarkdown.Key.block, at: index, effectiveRange: nil) as? String)
        if block == .ordered {
            let item = NSMenuItem(title: "Set Number…", action: #selector(setListNumber(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = index
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        return menu
    }

    @objc private func setListNumber(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, let storage = textStorage else { return }
        let para = (storage.string as NSString).paragraphRange(for: NSRange(location: index, length: 0))
        let current = (storage.attribute(RichMarkdown.Key.number, at: para.location, effectiveRange: nil) as? Int) ?? 1

        let alert = NSAlert()
        alert.messageText = "Set Number"
        alert.informativeText = "Number for this list item:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.stringValue = "\(current)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, let n = Int(field.stringValue) else { return }

        storage.addAttribute(RichMarkdown.Key.number, value: n, range: para)
        onContentChanged?()           // re-serialize to Markdown
        layoutManager?.invalidateDisplay(forCharacterRange: para)
        needsDisplay = true
    }
}

/// Whether a pasteboard (clipboard or drag) carries an image — raw image data
/// or a file with an image extension. Cheap: checks types/URLs, not file bytes.
func swPasteboardHasImage(_ pb: NSPasteboard) -> Bool {
    if pb.availableType(from: [.png, .tiff]) != nil { return true }
    if let urls = pb.readObjects(forClasses: [NSURL.self],
                                 options: [.urlReadingFileURLsOnly: true]) as? [URL] {
        let exts: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "webp"]
        return urls.contains { exts.contains($0.pathExtension.lowercased()) }
    }
    return false
}

/// Draws bullet/number markers for list paragraphs in the left margin. The
/// markers live only in layout — never in the text — so the saved Markdown and
/// all editing stay clean.
final class RichLayoutManager: NSLayoutManager {
    var markerColor: NSColor = .secondaryLabelColor

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        ns.enumerateSubstrings(in: charRange, options: [.byParagraphs, .substringNotRequired]) { _, paraRange, _, _ in
            guard paraRange.location < storage.length else { return }
            let block = RichMarkdown.BlockKind.decode(
                storage.attribute(RichMarkdown.Key.block, at: paraRange.location, effectiveRange: nil) as? String)
            guard block == .bullet || block == .ordered else { return }

            let para = storage.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle
            let headIndent = para?.headIndent ?? 24
            let font = (storage.attribute(.font, at: paraRange.location, effectiveRange: nil) as? NSFont)
                ?? NSFont.systemFont(ofSize: 14)

            let glyphRange = self.glyphRange(forCharacterRange: paraRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            let line = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)

            let marker = block == .ordered ? "\(self.orderedNumber(storage, ns, at: paraRange.location))." : "•"
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: self.markerColor]
            let m = (marker as NSString).size(withAttributes: attrs)
            let x = origin.x + headIndent - m.width - font.pointSize * 0.35
            let y = origin.y + line.minY + (line.height - m.height) / 2
            (marker as NSString).draw(at: NSPoint(x: max(origin.x + 2, x), y: y), withAttributes: attrs)
        }
    }

    /// The number to draw for an ordered item: the explicit `.swNumber` it
    /// carries, or — as a fallback — its 1-based position in the run.
    private func orderedNumber(_ storage: NSTextStorage, _ ns: NSString, at loc: Int) -> Int {
        if let stored = storage.attribute(RichMarkdown.Key.number, at: loc, effectiveRange: nil) as? Int {
            return stored
        }
        var n = 1
        var pos = ns.paragraphRange(for: NSRange(location: loc, length: 0)).location
        while pos > 0 {
            let prev = ns.paragraphRange(for: NSRange(location: pos - 1, length: 0))
            let b = RichMarkdown.BlockKind.decode(
                storage.attribute(RichMarkdown.Key.block, at: prev.location, effectiveRange: nil) as? String)
            if b == .ordered { n += 1; pos = prev.location } else { break }
        }
        return n
    }
}
