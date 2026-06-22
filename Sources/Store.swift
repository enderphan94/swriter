import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

/// What the main pane shows: visual writing, raw Markdown source, or the book
/// reading view.
enum Mode: String, CaseIterable { case write, source, read }

/// A registered vault the user can switch to in-app (MarkView's workspaces).
/// We only remember the pointer — forgetting one never touches the files.
struct Workspace: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var path: String
}

/// One visible row of the (flattened) sidebar tree, with its nesting depth.
struct TreeRow: Identifiable {
    let item: VaultItem
    let depth: Int
    var id: String { item.id }
}

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
    @Published private(set) var workspaces: [Workspace] = []
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

    // Sidebar state
    @Published var sortMode: SortMode = .nameAsc {
        didSet { persist(sortMode.rawValue, sortKey); refreshTree() }
    }
    @Published var searchQuery: String = ""
    /// Folder ids currently expanded in the tree (persisted per vault).
    @Published var expandedFolders: Set<String> = []

    // Panel sizing
    @Published var sidebarWidth: CGFloat = 250

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
    private let sortKey  = "SwriterSortMode"
    private let widthKey = "SwriterSidebarWidth"
    private let workspacesKey = "SwriterWorkspaces"
    private let expandedKey = "SwriterExpandedByVault"
    private var saveWork: DispatchWorkItem?

    var hasVault: Bool { vault != nil }
    var hasDocument: Bool { currentURL != nil }

    // MARK: Bootstrap

    func bootstrap() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: themeKey), let t = WriterTheme(rawValue: raw) { theme = t }
        let savedFont = d.double(forKey: fontKey)
        if savedFont >= 11 && savedFont <= 32 { fontSize = CGFloat(savedFont) }
        if let raw = d.string(forKey: sortKey), let s = SortMode(rawValue: raw) { sortMode = s }
        let w = d.double(forKey: widthKey); if w >= 180 && w <= 520 { sidebarWidth = CGFloat(w) }
        loadWorkspaces()

        if let saved = d.string(forKey: vaultKey) {
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
        flush()
        let v = Vault(root: url)
        vault = v
        vaultURL = url
        UserDefaults.standard.set(url.path, forKey: vaultKey)
        registerWorkspace(for: url)
        loadExpanded(for: url)
        searchQuery = ""
        refreshTree()
        closeDocument()
    }

    func closeVault() {
        flush()
        vault = nil
        vaultURL = nil
        tree = []
        expandedFolders = []
        closeDocument()
        UserDefaults.standard.removeObject(forKey: vaultKey)
    }

    func refreshTree() { tree = vault?.tree(sort: sortMode) ?? [] }

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

    /// Create a note and return its tree id so the sidebar can drop straight
    /// into inline rename (MarkView's behaviour).
    @discardableResult
    func newNote(in item: VaultItem? = nil, named: String = "Untitled") -> String? {
        guard let v = vault else { return nil }
        let dir = targetDir(for: item)
        guard let url = try? v.createNote(named: named, in: dir) else { return nil }
        if let item, item.isDirectory { expandedFolders.insert(item.id); saveExpanded() }
        refreshTree()
        openNote(at: url)
        return relativeID(url)
    }

    @discardableResult
    func newFolder(in item: VaultItem? = nil, named: String = "New Folder") -> String? {
        guard let v = vault else { return nil }
        let dir = targetDir(for: item)
        guard let url = try? v.createFolder(named: named, in: dir) else { return nil }
        if let item, item.isDirectory { expandedFolders.insert(item.id); saveExpanded() }
        refreshTree()
        return relativeID(url)
    }

    @discardableResult
    func duplicate(_ item: VaultItem) -> String? {
        guard let v = vault, let url = try? v.duplicate(item) else { return nil }
        refreshTree()
        if !item.isDirectory { openNote(at: url) }
        return relativeID(url)
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
        expandedFolders.remove(item.id)
        refreshTree()
        if affectsOpen { closeDocument() }
    }

    private func relativeID(_ url: URL) -> String {
        guard let root = vaultURL?.standardizedFileURL.path else { return url.lastPathComponent }
        let p = url.standardizedFileURL.path
        return p.hasPrefix(root)
            ? String(p.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : url.lastPathComponent
    }

    /// Move a dragged item into a folder (nil = vault root). Rejects dropping a
    /// folder into itself or a descendant, and no-op same-folder drops.
    func move(_ draggedID: String, intoFolderID folderID: String?) {
        guard let v = vault, let item = findItem(draggedID) else { return }
        let destDir = folderID.flatMap { findItem($0)?.url } ?? v.root
        let dest = destDir.standardizedFileURL.path
        let src = item.url.standardizedFileURL.path

        if item.url.deletingLastPathComponent().standardizedFileURL.path == dest { return } // already here
        if item.isDirectory, dest == src || dest.hasPrefix(src + "/") { NSSound.beep(); return }

        let openInside = currentURL.map { $0.path == src || $0.path.hasPrefix(src + "/") } ?? false
        guard let newURL = try? v.move(item, into: destDir) else { NSSound.beep(); return }

        if let folderID { expandedFolders.insert(folderID); saveExpanded() }
        if openInside, let cur = currentURL {
            let moved = URL(fileURLWithPath: cur.path.replacingOccurrences(of: src, with: newURL.path))
            currentURL = moved; docID = moved.path
        }
        refreshTree()
    }

    // MARK: Images

    /// Save image bytes into the vault and return the path relative to the note.
    private func saveImageBytes(_ data: Data, ext: String, base: String) -> String? {
        guard let v = vault, let note = currentURL,
              let rel = try? v.saveImage(data, ext: ext, base: base, noteURL: note) else { return nil }
        refreshTree()
        return rel
    }

    /// Paste handler: save a pasted image and return its vault-relative path
    /// (the rich editor turns it into an inline picture).
    func savePastedImage(_ pb: NSPasteboard) -> String? {
        guard let (data, ext) = Self.imageData(from: pb) else { return nil }
        return saveImageBytes(data, ext: ext, base: "image")
    }

    /// Source-mode paste: returns Markdown to insert, or nil for a normal paste.
    func insertImageFromPasteboard(_ pb: NSPasteboard) -> String? {
        savePastedImage(pb).map { "![](\($0))" }
    }

    /// "Insert Image…" — copy chosen files in and insert them into the active
    /// editor (as a picture in Write mode, as Markdown in Source mode).
    func importImage() {
        guard hasDocument, let tv = activeTextView else { NSSound.beep(); return }
        let panel = NSOpenPanel()
        panel.title = "Insert Image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            guard let rel = saveImageBytes(data, ext: ext,
                                           base: url.deletingPathExtension().lastPathComponent) else { continue }
            if let rt = tv as? RichTextView { rt.insertImage(path: rel, alt: "") }
            else { MarkdownFormatter.insertImage("![](\(rel))", into: tv) }
        }
    }

    /// Pull image bytes from a pasteboard: PNG, TIFF (→PNG), or a copied image file.
    private static func imageData(from pb: NSPasteboard) -> (Data, String)? {
        if let png = pb.data(forType: .png) { return (png, "png") }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { return (png, "png") }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let f = urls.first(where: { isImagePath($0.pathExtension) }),
           let data = try? Data(contentsOf: f) {
            return (data, f.pathExtension.lowercased())
        }
        return nil
    }

    private static func isImagePath(_ ext: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "webp"].contains(ext.lowercased())
    }

    // MARK: Sidebar — search, expand, flatten

    var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The tree to display: full, or pruned to search matches plus their
    /// ancestor folders.
    var filteredTree: [VaultItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tree }
        return prune(tree, query: q)
    }

    private func prune(_ items: [VaultItem], query: String) -> [VaultItem] {
        var out: [VaultItem] = []
        for item in items {
            if item.isDirectory {
                let kids = prune(item.children ?? [], query: query)
                if item.name.localizedCaseInsensitiveContains(query) || !kids.isEmpty {
                    var copy = item; copy.children = kids; out.append(copy)
                }
            } else if item.name.localizedCaseInsensitiveContains(query) {
                out.append(item)
            }
        }
        return out
    }

    /// The visible rows, flattened with their depth. Folders open by saved
    /// state, or all-open while searching so matches always show.
    func visibleRows() -> [TreeRow] {
        var rows: [TreeRow] = []
        let searching = isSearching
        func walk(_ items: [VaultItem], _ depth: Int) {
            for item in items {
                rows.append(TreeRow(item: item, depth: depth))
                if item.isDirectory, searching || expandedFolders.contains(item.id) {
                    walk(item.children ?? [], depth + 1)
                }
            }
        }
        walk(filteredTree, 0)
        return rows
    }

    /// Find a tree item by its id (used to commit an inline rename).
    func findItem(_ id: String) -> VaultItem? {
        func search(_ items: [VaultItem]) -> VaultItem? {
            for it in items {
                if it.id == id { return it }
                if let c = it.children, let f = search(c) { return f }
            }
            return nil
        }
        return search(tree)
    }

    func isExpanded(_ id: String) -> Bool { expandedFolders.contains(id) }

    func toggleExpand(_ id: String) {
        if expandedFolders.contains(id) { expandedFolders.remove(id) } else { expandedFolders.insert(id) }
        saveExpanded()
    }

    var anyExpanded: Bool { !expandedFolders.isEmpty }

    func expandAll()   { expandedFolders = allFolderIDs(tree); saveExpanded() }
    func collapseAll() { expandedFolders = []; saveExpanded() }

    private func allFolderIDs(_ items: [VaultItem]) -> Set<String> {
        var s = Set<String>()
        for it in items where it.isDirectory {
            s.insert(it.id); s.formUnion(allFolderIDs(it.children ?? []))
        }
        return s
    }

    private func loadExpanded(for url: URL) {
        let all = (UserDefaults.standard.dictionary(forKey: expandedKey) as? [String: [String]]) ?? [:]
        expandedFolders = Set(all[url.path] ?? [])
    }

    private func saveExpanded() {
        guard let path = vaultURL?.path else { return }
        var all = (UserDefaults.standard.dictionary(forKey: expandedKey) as? [String: [String]]) ?? [:]
        all[path] = Array(expandedFolders)
        UserDefaults.standard.set(all, forKey: expandedKey)
    }

    // MARK: Panel sizing

    func persistSidebarWidth() { persist(Double(sidebarWidth), widthKey) }

    func cycleMode() {
        let all = Mode.allCases
        if let i = all.firstIndex(of: mode) { mode = all[(i + 1) % all.count] }
    }

    // MARK: Workspaces (in-app vault switching)

    var activeWorkspaceID: String? {
        guard let p = vaultURL?.path else { return nil }
        return workspaces.first { $0.path == p }?.id
    }

    private func loadWorkspaces() {
        if let data = UserDefaults.standard.data(forKey: workspacesKey),
           let list = try? JSONDecoder().decode([Workspace].self, from: data) {
            workspaces = list
        }
    }

    private func saveWorkspaces() {
        if let data = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(data, forKey: workspacesKey)
        }
    }

    private func registerWorkspace(for url: URL) {
        guard !workspaces.contains(where: { $0.path == url.path }) else { return }
        workspaces.append(Workspace(id: "ws_" + String(UUID().uuidString.prefix(8)),
                                    name: url.lastPathComponent, path: url.path))
        saveWorkspaces()
    }

    func switchWorkspace(_ id: String) {
        guard let ws = workspaces.first(where: { $0.id == id }) else { return }
        let url = URL(fileURLWithPath: ws.path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            removeWorkspace(id); return   // folder vanished — forget the stale pointer
        }
        if url.path != vaultURL?.path { openVault(at: url) }
    }

    func renameWorkspace(_ id: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[i].name = clean
        saveWorkspaces()
    }

    func removeWorkspace(_ id: String) {
        let wasActive = id == activeWorkspaceID
        workspaces.removeAll { $0.id == id }
        saveWorkspaces()
        if wasActive {
            if let first = workspaces.first { openVault(at: URL(fileURLWithPath: first.path)) }
            else { closeVault() }
        }
    }

    /// Register a folder as a vault and switch to it (optionally creating it).
    func addVault(at url: URL, create: Bool) {
        if create { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        openVault(at: url)
        if create { seedWelcomeIfEmpty() }
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
