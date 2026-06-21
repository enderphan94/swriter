import SwiftUI
import AppKit
import Combine

/// What the main pane shows.
enum Mode: String { case write, read }

/// Drives the About window's update UI.
enum UpdateState {
    case idle, checking, upToDate
    case available(UpdateInfo)
    case downloading
    case failed(String)
}

/// The single source of truth. Holds the open vault, the note currently being
/// edited, and view settings. Text edits are debounced to disk; structural
/// actions (new/rename/delete) persist immediately and refresh the tree.
final class AppStore: ObservableObject {

    // Vault
    @Published private(set) var vaultURL: URL?
    @Published private(set) var tree: [VaultItem] = []
    private var vault: Vault?

    // Open document
    @Published private(set) var currentURL: URL?
    /// Authoritative text of the open note; the editor reports edits here.
    @Published var text: String = ""
    @Published private(set) var dirty: Bool = false
    /// Changes whenever a *different* note is opened, telling the editor to
    /// reload its contents (vs. leaving in-progress user edits alone).
    @Published private(set) var docID: String = ""

    // View settings
    @Published var mode: Mode = .write
    @Published var theme: WriterTheme = .light { didSet { persist(theme.rawValue, themeKey) } }
    @Published var fontSize: CGFloat = 17 { didSet { persist(Double(fontSize), fontKey) } }
    @Published var focusMode: Bool = false
    @Published var sidebarVisible: Bool = true

    // Updates
    @Published var showAbout: Bool = false
    @Published var updateState: UpdateState = .idle
    @Published var pendingUpdate: UpdateInfo? = nil
    private var didLaunchUpdateCheck = false

    /// The live editor view, registered by the editor's coordinator so toolbar
    /// actions and PDF export can reach the current text.
    weak var activeTextView: NSTextView?

    private let vaultKey = "SwriterVaultPath"
    private let themeKey = "SwriterTheme"
    private let fontKey  = "SwriterFontSize"
    private var saveWork: DispatchWorkItem?

    var hasVault: Bool { vault != nil }
    var hasDocument: Bool { currentURL != nil }

    // MARK: Bootstrap

    func bootstrap() {
        if let raw = UserDefaults.standard.string(forKey: themeKey),
           let t = WriterTheme(rawValue: raw) { theme = t }
        let savedFont = UserDefaults.standard.double(forKey: fontKey)
        if savedFont >= 11 && savedFont <= 32 { fontSize = CGFloat(savedFont) }
        if let saved = UserDefaults.standard.string(forKey: vaultKey) {
            let url = URL(fileURLWithPath: saved)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                openVault(at: url)
            }
        }
    }

    private func persist(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: Vault lifecycle

    func createVault(at url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        openVault(at: url)
        seedWelcomeIfEmpty()
    }

    func openVault(at url: URL) {
        let v = Vault(root: url)
        vault = v
        vaultURL = url
        UserDefaults.standard.set(url.path, forKey: vaultKey)
        refreshTree()
        closeDocument()
    }

    func closeVault() {
        flush()
        vault = nil
        vaultURL = nil
        tree = []
        closeDocument()
        UserDefaults.standard.removeObject(forKey: vaultKey)
    }

    func refreshTree() { tree = vault?.tree() ?? [] }

    func revealInFinder() {
        guard let url = currentURL ?? vaultURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Drop a friendly first note in a brand-new vault.
    private func seedWelcomeIfEmpty() {
        guard let v = vault, tree.isEmpty else { return }
        if let url = try? v.createNote(named: "Welcome", in: v.root) {
            try? v.write(Self.welcomeMarkdown, to: url)
            refreshTree()
            openNote(at: url)
        }
    }

    // MARK: Document lifecycle

    func openNote(at url: URL) {
        guard url != currentURL else { return }
        flush()
        currentURL = url
        text = vault?.read(url) ?? ""
        docID = url.path
        dirty = false
    }

    func closeDocument() {
        flush()
        currentURL = nil
        text = ""
        docID = ""
        dirty = false
    }

    /// Called by the editor on every keystroke.
    func onTextChanged(_ newValue: String) {
        guard newValue != text else { return }
        text = newValue
        dirty = true
        scheduleSave()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Write pending edits to disk now.
    func flush() {
        saveWork?.cancel(); saveWork = nil
        guard dirty, let url = currentURL, let v = vault else { return }
        try? v.write(text, to: url)
        dirty = false
        // A title change in the first heading doesn't rename the file — keep
        // filename stable; the user renames explicitly in the sidebar.
    }

    // MARK: Structural actions

    /// Parent directory for new items: the selected folder, the open note's
    /// folder, or the vault root.
    private func targetDir(for item: VaultItem?) -> URL {
        if let item {
            return item.isDirectory ? item.url : item.url.deletingLastPathComponent()
        }
        if let cur = currentURL { return cur.deletingLastPathComponent() }
        return vault?.root ?? vaultURL ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func newNote(in item: VaultItem? = nil, named: String = "Untitled") {
        guard let v = vault else { return }
        let dir = targetDir(for: item)
        guard let url = try? v.createNote(named: named, in: dir) else { return }
        refreshTree()
        openNote(at: url)
    }

    func newFolder(in item: VaultItem? = nil, named: String = "New Folder") {
        guard let v = vault else { return }
        let dir = targetDir(for: item)
        _ = try? v.createFolder(named: named, in: dir)
        refreshTree()
    }

    func rename(_ item: VaultItem, to newName: String) {
        guard let v = vault, let url = try? v.rename(item, to: newName) else { return }
        let wasOpen = currentURL == item.url ||
            (item.isDirectory && currentURL?.path.hasPrefix(item.url.path) == true)
        refreshTree()
        if wasOpen && !item.isDirectory { currentURL = url; docID = url.path }
    }

    func delete(_ item: VaultItem) {
        guard let v = vault else { return }
        let affectsOpen = currentURL == item.url ||
            (item.isDirectory && currentURL?.path.hasPrefix(item.url.path) == true)
        v.delete(item)
        refreshTree()
        if affectsOpen { closeDocument() }
    }

    // MARK: Derived stats

    var wordCount: Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    var characterCount: Int { text.count }

    /// Minutes at a calm 200 wpm reading pace, never below 1 for non-empty text.
    var readingMinutes: Int {
        wordCount == 0 ? 0 : max(1, Int((Double(wordCount) / 200.0).rounded(.up)))
    }

    var documentTitle: String {
        currentURL.map { $0.deletingPathExtension().lastPathComponent } ?? "Swriter"
    }

    // MARK: Updates

    func checkForUpdatesOnLaunch() {
        guard !didLaunchUpdateCheck else { return }
        didLaunchUpdateCheck = true
        Task { await runUpdateCheck(promptIfAvailable: true) }
    }

    func checkForUpdates() {
        Task { await runUpdateCheck(promptIfAvailable: false) }
    }

    @MainActor
    private func runUpdateCheck(promptIfAvailable: Bool) async {
        updateState = .checking
        do {
            let info = try await Updater.check()
            if info.isAvailable {
                updateState = .available(info)
                if promptIfAvailable { pendingUpdate = info }
            } else {
                updateState = .upToDate
            }
        } catch {
            updateState = .failed((error as? UpdaterError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func applyUpdate(_ info: UpdateInfo) {
        guard let url = info.downloadURL else { return }
        pendingUpdate = nil
        showAbout = true
        updateState = .downloading
        Task {
            do {
                try await Updater.apply(downloadURL: url)
                await MainActor.run { self.flush(); exit(0) }
            } catch {
                await MainActor.run {
                    self.updateState = .failed((error as? UpdaterError)?.errorDescription ?? error.localizedDescription)
                }
            }
        }
    }

    static let welcomeMarkdown = """
    # Welcome to Swriter

    A calm place to **write**, *read*, and keep notes — like working in a real
    book. Everything you write is a plain Markdown file you own, kept in the
    vault folder you chose.

    ## Writing

    Use the toolbar or these shortcuts as you type:

    - **Bold** — ⌘B
    - *Italic* — ⌘I
    - `Inline code` — ⌘E
    - [Links](https://ia.net/writer) — ⌘K
    - Headings — ⌘1 … ⌘3

    > Markdown stays visible but quiet while you write, then renders to a clean
    > page in Reading mode.

    ## A table, because you can

    | Tool   | Shortcut |
    |--------|----------|
    | Bold   | ⌘B       |
    | Italic | ⌘I       |
    | Code   | ⌘E       |

    ## Make a book

    When a piece is ready, choose **File ▸ Export to PDF (A5)** to lay it out on
    A5 pages — the standard size for a printed paperback.

    Happy writing.
    """
}
