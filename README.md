<p align="center"><strong>Swriter</strong></p>
<p align="center">A calm, native macOS Markdown writer for notes and books.</p>

---

Swriter is a focused writing app in the spirit of [iA Writer](https://ia.net/writer):
you write in plain Markdown, the syntax stays quiet while you type, and a clean
**Reading** view renders it like a finished book page. When a piece is ready,
export it to a print-ready **A5 PDF** — the standard trim size for a paperback.

Everything you write is a plain `.md` file in a **vault** folder you choose, so
your work is yours: back it up, sync it over iCloud, or open the same folder in
Obsidian, VS Code, or iA Writer.

There is no account, no cloud service, and no tracking.

## Features

- **Distraction-free editor** — a monospaced, centered writing column with live,
  understated Markdown styling (the `**` stays visible but faint; the words
  between turn bold).
- **Focus mode** — dims everything but the paragraph you're working on.
- **Writing tools** — a toolbar and keyboard shortcuts for bold, italic,
  strikethrough, inline code, headings, bulleted/numbered lists, quotes, links,
  tables, code blocks, and horizontal rules.
- **Reading mode** — your note rendered in a serif face with real headings,
  block quotes, lists, fenced code, and proper tables.
- **Split view** — editor and live preview side by side, with a draggable,
  remembered divider. The sidebar width is draggable too (double-click a
  divider to reset).
- **A5 PDF export** — paginated onto 148 × 210 mm pages with margins and page
  numbers, ready for book printing.
- **Vault** — a folder of `.md` files with a tree sidebar. Right-click for New
  Note / New Folder / Rename / Duplicate / Reveal in Finder / Move to Trash;
  double-click to rename inline; search, sort (name / modified / created), and
  expand-or-collapse all.
- **Switch vaults in-app** — a workspace dropdown in the sidebar header to
  switch between vaults, add or create new ones, rename, or remove one from the
  list (which only forgets the pointer — your files are never deleted).
- **Three themes** — Light, Sepia, and Dark.
- **Self-update** — checks GitHub Releases on launch and offers a one-click
  update, with a manual check in **About Swriter**.

## Keyboard shortcuts

| Action | Shortcut | Action | Shortcut |
|--------|----------|--------|----------|
| Bold | ⌘B | New Note | ⌘N |
| Italic | ⌘I | New Folder | ⇧⌘N |
| Inline code | ⌘E | Save | ⌘S |
| Strikethrough | ⇧⌘X | Export to PDF (A5) | ⇧⌘E |
| Heading 1–3 | ⌘1 / ⌘2 / ⌘3 | Cycle view (Write/Split/Read) | ⇧⌘R |
| Bulleted list | ⇧⌘8 | Focus mode | ⇧⌘F |
| Numbered list | ⇧⌘7 | Toggle sidebar | ⌘\ |
| Quote | ⇧⌘' | Bigger / smaller text | ⌘+ / ⌘- |
| Link | ⌘K | | |

## Build

No Xcode project and no dependencies — just the Swift toolchain that ships with
Xcode or the Command Line Tools.

```bash
./build.sh        # → dist/Swriter.app
./make_dmg.sh     # → dist/Swriter-<version>.dmg (optional)
```

Then open `dist/Swriter.app`. The build targets Apple Silicon, macOS 13+.

> The app is ad-hoc signed (unsigned for distribution). On first launch,
> right-click **Swriter → Open → Open** to clear Gatekeeper once.

## How it works

- **`Sources/`** — the whole app, compiled directly by `swiftc`.
  - `App.swift` / `MainView.swift` / `SidebarView.swift` — SwiftUI shell, menus, layout.
  - `MarkdownEditor.swift` + `MarkdownHighlighter.swift` — the `NSTextView`-backed
    editor with live syntax styling and Focus mode.
  - `MarkdownFormatter.swift` — the writing tools (toolbar + shortcuts).
  - `Markdown.swift` + `ReadingView.swift` — the renderer and book-like reading mode.
  - `PDFExport.swift` — A5 pagination via TextKit.
  - `Vault.swift` / `Store.swift` — the folder-of-Markdown model and app state.
  - `Updater.swift` / `AboutView.swift` — GitHub-release self-update.
- **`build.sh`** compiles the sources, renders the icon (`scripts/make_icon.swift`),
  writes `Info.plist`, and ad-hoc signs the bundle.

## License

MIT.
