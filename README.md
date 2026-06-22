<p align="center"><strong>Swriter</strong></p>
<p align="center">A calm, native macOS Markdown writer for notes and books.</p>

---

Swriter is a focused writing app. You write **visually** — like Apple Notes or
Word — with real bold, real headings, and real inline images, and **no Markdown
symbols on screen**. Underneath, every note is a plain `.md` file; the Markdown
is just the format, kept in the background. A clean **Reading** view renders the
page like a finished book, and when a piece is ready you can export it to a
print-ready **A5 PDF** — the standard trim size for a paperback.

Everything you write is a plain `.md` file in a **vault** folder you choose, so
your work is yours: back it up, sync it over iCloud, or open the same folder in
Obsidian, VS Code, or iA Writer.

There is no account, no cloud service, and no tracking.

## Features

- **Visual (WYSIWYG) editor** — write in formatted text with no Markdown symbols
  in sight: bold, italics, headings, bulleted/numbered lists, quotes, code, links,
  and inline images all show as themselves. The document is saved as Markdown
  automatically (round-trip tested so your text is never mangled).
- **Three views** — **Write** (visual), **Source** (raw Markdown, for technical
  edits), and **Read** (a serif book page). Switch from the toolbar or cycle with
  ⇧⌘R.
- **Writing tools** — a toolbar and keyboard shortcuts for bold, italic,
  strikethrough, inline code, headings, bulleted/numbered lists, quotes, links,
  images, tables, code blocks, and horizontal rules.
- **A5 PDF export** — paginated onto 148 × 210 mm pages with margins and page
  numbers, ready for book printing.
- **Vault** — a folder of `.md` files with a tree sidebar. Right-click for New
  Note / New Folder / Rename / Duplicate / Reveal in Finder / Move to Trash;
  double-click to rename inline; **drag a note or folder onto another folder (or
  the root) to move it**; search, sort (name / modified / created), and
  expand-or-collapse all.
- **Images** — paste an image straight into a note, or **Insert Image…** to pick
  files. They're copied into an `assets/` folder in the vault and shown as real
  pictures while you write, in Reading mode, and in the exported PDF.
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
| Heading 1–3 | ⌘1 / ⌘2 / ⌘3 | Cycle view (Write/Source/Read) | ⇧⌘R |
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
  - `RichMarkdown.swift` — parses Markdown into editable formatted text and
    serializes it back (the visual ⇄ Markdown bridge, round-trip tested).
  - `RichEditor.swift` + `RichFormatter.swift` — the WYSIWYG editor (Write mode),
    inline images, list markers, and rich formatting.
  - `MarkdownEditor.swift` + `MarkdownHighlighter.swift` — the raw-Markdown
    Source editor with live syntax styling and Focus mode.
  - `MarkdownFormatter.swift` — Source-mode writing tools.
  - `Markdown.swift` + `ReadingView.swift` — the renderer and book-like reading mode.
  - `PDFExport.swift` — A5 pagination via TextKit.
  - `Vault.swift` / `Store.swift` — the folder-of-Markdown model and app state.
  - `Updater.swift` / `AboutView.swift` — GitHub-release self-update.
- **`build.sh`** compiles the sources, renders the icon (`scripts/make_icon.swift`),
  writes `Info.plist`, and ad-hoc signs the bundle.

## License

MIT.
