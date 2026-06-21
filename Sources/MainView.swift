import SwiftUI

/// The working window: vault sidebar on the left, the writing/reading pane on
/// the right, a formatting bar while writing, and a quiet status line.
struct MainView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            if store.sidebarVisible {
                SidebarView()
                Divider()
            }
            content
        }
        .toolbar { toolbar }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            if store.hasDocument {
                if store.mode == .write {
                    FormattingBar()
                    Divider()
                }
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
        if store.mode == .write {
            MarkdownEditor(
                docID: store.docID,
                initialText: store.text,
                theme: store.theme,
                fontSize: store.fontSize,
                focusMode: store.focusMode,
                onChange: { store.onTextChanged($0) },
                onActivate: { store.activeTextView = $0 })
        } else {
            ReadingView(markdown: store.text, theme: store.theme, bodySize: store.fontSize)
        }
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
            Button { store.sidebarVisible.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")
        }

        ToolbarItem(placement: .principal) {
            Text(store.documentTitle).font(.headline)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("", selection: $store.mode) {
                Image(systemName: "pencil").tag(Mode.write)
                Image(systemName: "book").tag(Mode.read)
            }
            .pickerStyle(.segmented).help("Writing / Reading")
            .disabled(!store.hasDocument)

            Button { store.focusMode.toggle() } label: {
                Image(systemName: store.focusMode ? "scope" : "circle.dashed")
            }
            .help("Focus Mode (⇧⌘F)")

            Menu {
                ForEach(WriterTheme.allCases) { t in
                    Button { store.theme = t } label: {
                        Label(t.title, systemImage: t.symbol)
                    }
                }
            } label: {
                Image(systemName: store.theme.symbol)
            }
            .help("Theme")

            Button { store.exportPDF() } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export to PDF (A5)")
            .disabled(!store.hasDocument)
        }
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
                .menuStyle(.borderlessButton).frame(width: 38).help("Heading")
                bar
                btn("list.bullet", "Bulleted List (⇧⌘8)") { store.format(.bulletList) }
                btn("list.number", "Numbered List (⇧⌘7)") { store.format(.numberList) }
                btn("text.quote", "Quote (⇧⌘')") { store.format(.quote) }
                bar
                btn("link", "Link (⌘K)") { store.format(.link) }
                btn("tablecells", "Insert Table") { store.format(.table) }
                btn("curlybraces", "Code Block") { store.format(.codeBlock) }
                btn("minus", "Horizontal Rule") { store.format(.horizontalRule) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .background(.bar)
    }

    private func btn(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 26, height: 22)
        }
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
                Circle()
                    .fill(store.dirty ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
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
