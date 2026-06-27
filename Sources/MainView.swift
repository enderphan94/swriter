import SwiftUI
import AppKit

/// The working window: a resizable vault sidebar, then the pane — visual
/// Writing, raw Markdown Source, or book Reading — with a formatting bar while
/// editing and a quiet status line.
struct MainView: View {
    @EnvironmentObject var store: AppStore
    @State private var baseSidebar: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            if store.sidebarVisible {
                SidebarView().frame(width: store.sidebarWidth)
                ResizeHandle(
                    onDrag: { tx in
                        let base = baseSidebar ?? store.sidebarWidth
                        if baseSidebar == nil { baseSidebar = base }
                        store.sidebarWidth = min(520, max(180, base + tx))
                    },
                    onEnd: { baseSidebar = nil; store.persistSidebarWidth() },
                    onDoubleClick: { store.sidebarWidth = 250; store.persistSidebarWidth() })
            }
            content
        }
        .toolbar { toolbar }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            if store.hasDocument {
                if store.mode != .read { FormattingBar(); Divider() }
                pane
                Divider()
                StatusBar()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(store.theme.bg)
    }

    @ViewBuilder private var pane: some View {
        switch store.mode {
        case .write:  richEditor
        case .source: sourceEditor
        case .read:   readingView
        }
    }

    /// Visual (WYSIWYG) writing — the default.
    private var richEditor: some View {
        RichEditor(
            docID: store.docID,
            markdown: store.text,
            theme: store.theme,
            fontSize: store.fontSize,
            baseURL: store.currentURL?.deletingLastPathComponent(),
            onChange: { store.onTextChanged($0) },
            onActivate: { store.activeTextView = $0 },
            onResign: { store.resignActiveTextView($0) },
            onImageSave: { store.savePastedImage($0) })
    }

    /// Raw Markdown source — the technical view.
    private var sourceEditor: some View {
        MarkdownEditor(
            docID: store.docID,
            initialText: store.text,
            theme: store.theme,
            fontSize: store.fontSize,
            focusMode: store.focusMode,
            onChange: { store.onTextChanged($0) },
            onActivate: { store.activeTextView = $0 },
            onResign: { store.resignActiveTextView($0) },
            onImagePaste: { store.insertImageFromPasteboard($0) })
    }

    private var readingView: some View {
        ReadingView(markdown: store.text, theme: store.theme, bodySize: store.fontSize,
                    baseURL: store.currentURL?.deletingLastPathComponent())
            .frame(maxWidth: .infinity)
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Spacer()
            AppGlyph(size: 64).opacity(0.85)
            Text("Select a note, or create one to start writing.")
                .foregroundStyle(.secondary)
            Button("New Note") { store.newNote() }.buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { store.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("Toggle Sidebar (⌘\\)")
        }
        ToolbarItem(placement: .principal) {
            Text(store.documentTitle).font(.headline)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("", selection: $store.mode) {
                Image(systemName: "textformat").tag(Mode.write)
                Image(systemName: "chevron.left.forwardslash.chevron.right").tag(Mode.source)
                Image(systemName: "book").tag(Mode.read)
            }
            .pickerStyle(.segmented).help("Writing / Source / Reading")
            .disabled(!store.hasDocument)

            Button { store.focusMode.toggle() } label: {
                Image(systemName: store.focusMode ? "scope" : "circle.dashed")
            }
            .help("Focus Mode (⇧⌘F)")

            Menu {
                ForEach(WriterTheme.allCases) { t in
                    Button { store.theme = t } label: { Label(t.title, systemImage: t.symbol) }
                }
            } label: {
                Image(systemName: store.theme.symbol)
            }
            .help("Theme")

            Button { store.exportPDF() } label: { Image(systemName: "square.and.arrow.up") }
                .help("Export to PDF (A5)")
                .disabled(!store.hasDocument)
        }
    }
}

/// A draggable gutter between two panels. Reports the cumulative drag so the
/// caller can apply it to a width captured at gesture start; double-click resets.
struct ResizeHandle: View {
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    let onDoubleClick: () -> Void
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .overlay(
                Rectangle()
                    .fill(hovering ? Color.accentColor : Color.gray.opacity(0.22))
                    .frame(width: hovering ? 2 : 1))
            .contentShape(Rectangle())
            .onHover { h in
                hovering = h
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { onDrag($0.translation.width) }
                    .onEnded { _ in onEnd() })
            .onTapGesture(count: 2, perform: onDoubleClick)
    }
}

/// The Markdown writing tools, mirroring a web editor's toolbar.
struct FormattingBar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                btn("bold", "Bold (⌘B)") { store.format(.bold) }
                btn("italic", "Italic (⌘I)") { store.format(.italic) }
                btn("strikethrough", "Strikethrough (⇧⌘X)") { store.format(.strikethrough) }
                btn("chevron.left.forwardslash.chevron.right", "Inline Code (⌘E)") { store.format(.code) }
                bar
                Menu {
                    Button("Heading 1") { store.format(.heading(1)) }
                    Button("Heading 2") { store.format(.heading(2)) }
                    Button("Heading 3") { store.format(.heading(3)) }
                } label: {
                    Image(systemName: "textformat.size")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 38).help("Heading")
                bar
                btn("list.bullet", "Bulleted List (⇧⌘8)") { store.format(.bulletList) }
                btn("list.number", "Numbered List (⇧⌘7)") { store.format(.numberList) }
                btn("text.quote", "Quote (⇧⌘')") { store.format(.quote) }
                bar
                btn("link", "Link (⌘K)") { store.format(.link) }
                btn("photo", "Insert Image") { store.importImage() }
                btn("tablecells", "Insert Table") { store.format(.table) }
                btn("curlybraces", "Code Block") { store.format(.codeBlock) }
                btn("minus", "Horizontal Rule") { store.format(.horizontalRule) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .background(.bar)
    }

    private func btn(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 26, height: 22) }
            .buttonStyle(.borderless).help(help)
    }

    private var bar: some View {
        Divider().frame(height: 18).padding(.horizontal, 3)
    }
}

/// Word count, reading time, save state — the calm footer.
struct StatusBar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            Text("\(store.wordCount) words")
            Text("·")
            Text("\(store.characterCount) characters")
            if store.readingMinutes > 0 {
                Text("·")
                Text("\(store.readingMinutes) min read")
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(store.dirty ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(store.dirty ? "Editing…" : "Saved")
            }
            Text("·")
            Label(store.theme.title, systemImage: store.theme.symbol)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.bar)
    }
}
