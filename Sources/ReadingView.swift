import SwiftUI
import AppKit

/// Book-like reading mode: the note rendered to finished prose in a serif face,
/// centered in a comfortable column. Read-only but selectable, with live links.
struct ReadingView: NSViewRepresentable {
    let markdown: String
    let theme: WriterTheme
    let bodySize: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true

        let tv = WriterTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.drawsBackground = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 4
        tv.measure = 660
        tv.linkTextAttributes = [.foregroundColor: theme.accent,
                                 .underlineStyle: NSUnderlineStyle.single.rawValue,
                                 .cursor: NSCursor.pointingHand]
        scroll.documentView = tv
        context.coordinator.textView = tv
        render(into: tv, scroll: scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        let key = "\(markdown.hashValue)|\(theme.rawValue)|\(bodySize)"
        if context.coordinator.lastKey != key {
            render(into: tv, scroll: scroll, context: context)
        }
    }

    private func render(into tv: WriterTextView, scroll: NSScrollView, context: Context) {
        tv.backgroundColor = theme.background
        scroll.backgroundColor = theme.background
        let attr = MarkdownRenderer.attributed(markdown, theme: theme, bodySize: bodySize, forPrint: false)
        tv.textStorage?.setAttributedString(attr)
        tv.refreshInset()
        context.coordinator.lastKey = "\(markdown.hashValue)|\(theme.rawValue)|\(bodySize)"
        tv.scroll(.zero)
    }

    final class Coordinator {
        weak var textView: WriterTextView?
        var lastKey: String = ""
    }
}
