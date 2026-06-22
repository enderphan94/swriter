import AppKit

/// Lays the rendered note out on A5 pages and writes a print-ready PDF — the
/// standard trim size for a paperback book. Pagination is done with TextKit:
/// one fixed-size text container per page, flowed until the text runs out.
enum PDFExport {

    // A5 = 148 × 210 mm, at 72 pt/inch.
    static let pageSize = CGSize(width: 419.53, height: 595.28)
    static let margin = NSEdgeInsets(top: 60, left: 54, bottom: 66, right: 54)

    static func write(markdown: String, title: String, theme: WriterTheme,
                      baseURL: URL?, to url: URL) throws {
        let attr = MarkdownRenderer.attributed(markdown, theme: theme, bodySize: 11.5,
                                               forPrint: true, baseURL: baseURL)

        let storage = NSTextStorage(attributedString: attr)
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = false
        storage.addLayoutManager(layout)

        let textRect = CGRect(
            x: margin.left, y: margin.top,
            width: pageSize.width - margin.left - margin.right,
            height: pageSize.height - margin.top - margin.bottom)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw ExportError.contextFailed
        }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.contextFailed
        }

        var glyph = 0
        var page = 1
        repeat {
            let container = NSTextContainer(size: textRect.size)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let range = layout.glyphRange(for: container)

            ctx.beginPDFPage(nil)
            ctx.saveGState()
            // Flip to a top-left origin so TextKit draws right-side up.
            ctx.translateBy(x: 0, y: pageSize.height)
            ctx.scaleBy(x: 1, y: -1)
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx

            let origin = CGPoint(x: textRect.minX, y: textRect.minY)
            layout.drawBackground(forGlyphRange: range, at: origin)
            layout.drawGlyphs(forGlyphRange: range, at: origin)
            drawFooter(page: page, title: title)

            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
            ctx.endPDFPage()

            glyph = NSMaxRange(range)
            page += 1
        } while glyph < layout.numberOfGlyphs

        ctx.closePDF()
        try data.write(to: url)
    }

    /// Centered page number near the foot, with the title whispered above it.
    private static func drawFooter(page: Int, title: String) {
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Typeface.serif(8.5),
            .foregroundColor: NSColor.gray,
            .paragraphStyle: para,
        ]
        let footer = NSAttributedString(string: "\(title)   ·   \(page)", attributes: attrs)
        let width = pageSize.width - margin.left - margin.right
        let rect = CGRect(x: margin.left, y: pageSize.height - margin.bottom + 24,
                          width: width, height: 14)
        footer.draw(in: rect)
    }

    enum ExportError: LocalizedError {
        case contextFailed
        var errorDescription: String? { "Couldn't create the PDF context." }
    }
}

extension AppStore {
    /// Ask where to save, render the open note to an A5 PDF, and reveal it.
    func exportPDF() {
        flush()
        guard hasDocument, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep(); return
        }
        let panel = NSSavePanel()
        panel.title = "Export to PDF (A5)"
        panel.nameFieldStringValue = documentTitle + ".pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try PDFExport.write(markdown: text, title: documentTitle, theme: theme,
                                baseURL: currentURL?.deletingLastPathComponent(), to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Export Failed"
            alert.runModal()
        }
    }
}
