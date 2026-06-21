import SwiftUI
import AppKit

/// The writing surface: a plain-text `NSTextView` with live Markdown styling,
/// a centered measure (like a book column), and an optional Focus mode. SwiftUI
/// can't style text in place, so this bridges to AppKit.
struct MarkdownEditor: NSViewRepresentable {
    let docID: String
    let initialText: String
    let theme: WriterTheme
    let fontSize: CGFloat
    let focusMode: Bool
    var onChange: (String) -> Void
    var onActivate: (NSTextView?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true

        let tv = WriterTextView(frame: .zero)
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.usesFontPanel = false
        tv.usesRuler = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 4
        tv.delegate = context.coordinator
        tv.string = initialText

        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.scrollView = scroll
        context.coordinator.docID = docID

        applyChrome(tv, scroll)
        MarkdownHighlighter.apply(to: tv.textStorage!, theme: theme, size: fontSize)
        if focusMode { applyFocus(tv) }
        onActivate(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        guard let tv = c.textView else { return }
        c.parent = self

        if c.docID != docID {
            c.docID = docID
            c.isProgrammatic = true
            tv.string = initialText
            c.isProgrammatic = false
            applyChrome(tv, scroll)
            MarkdownHighlighter.apply(to: tv.textStorage!, theme: theme, size: fontSize)
            if focusMode { applyFocus(tv) }
            tv.scroll(.zero)
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
            return
        }

        if c.theme != theme || c.fontSize != fontSize || c.focusMode != focusMode {
            applyChrome(tv, scroll)
            MarkdownHighlighter.apply(to: tv.textStorage!, theme: theme, size: fontSize)
            if focusMode { applyFocus(tv) }
        }
        c.theme = theme; c.fontSize = fontSize; c.focusMode = focusMode
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.parent.onActivate(nil)
    }

    private func applyChrome(_ tv: WriterTextView, _ scroll: NSScrollView) {
        tv.backgroundColor = theme.background
        scroll.backgroundColor = theme.background
        tv.insertionPointColor = theme.text
        tv.selectedTextAttributes = [.backgroundColor: theme.selection]
        tv.typingAttributes = [.font: Typeface.editor(fontSize), .foregroundColor: theme.text]
        tv.measure = 720
        tv.refreshInset()
    }

    fileprivate func applyFocus(_ tv: WriterTextView) {
        MarkdownHighlighter.applyFocus(to: tv.textStorage!, selection: tv.selectedRange(),
                                       theme: theme, size: fontSize)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: WriterTextView?
        weak var scrollView: NSScrollView?
        var docID: String = ""
        var theme: WriterTheme = .light
        var fontSize: CGFloat = 17
        var focusMode = false
        var isProgrammatic = false

        init(_ parent: MarkdownEditor) {
            self.parent = parent
            self.theme = parent.theme
            self.fontSize = parent.fontSize
            self.focusMode = parent.focusMode
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammatic, let tv = textView, let storage = tv.textStorage else { return }
            parent.onChange(tv.string)
            let sel = tv.selectedRange()
            MarkdownHighlighter.apply(to: storage, theme: parent.theme, size: parent.fontSize)
            if parent.focusMode {
                MarkdownHighlighter.applyFocus(to: storage, selection: sel,
                                               theme: parent.theme, size: parent.fontSize)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard parent.focusMode, !isProgrammatic, let tv = textView, let storage = tv.textStorage
            else { return }
            MarkdownHighlighter.applyFocus(to: storage, selection: tv.selectedRange(),
                                           theme: parent.theme, size: parent.fontSize)
        }
    }
}

/// An `NSTextView` that keeps text in a centered column of at most `measure`
/// points, padding the sides so long lines never sprawl — the comfortable
/// reading width of a printed page.
final class WriterTextView: NSTextView {
    var measure: CGFloat = 720

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshInset()
    }

    func refreshInset() {
        let side = max(28, (bounds.width - measure) / 2)
        let inset = NSSize(width: side, height: 44)
        if textContainerInset != inset { textContainerInset = inset }
    }
}
