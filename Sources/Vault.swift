import Foundation

/// A node in the vault tree: either a folder or a `.md` note. `children` is
/// non-nil for folders (even when empty, so they stay expandable) and nil for
/// notes.
struct VaultItem: Identifiable, Hashable {
    let id: String          // POSIX path relative to the vault root
    let name: String        // display name — notes drop the ".md"
    let url: URL
    let isDirectory: Bool
    let modified: Date
    let created: Date
    var children: [VaultItem]?
}

/// Sidebar sort order, matching MarkView's six options.
enum SortMode: String, CaseIterable, Identifiable {
    case nameAsc, nameDesc, modifiedDesc, modifiedAsc, createdDesc, createdAsc
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAsc:      return "Name A → Z"
        case .nameDesc:     return "Name Z → A"
        case .modifiedDesc: return "Modified (new first)"
        case .modifiedAsc:  return "Modified (old first)"
        case .createdDesc:  return "Created (new first)"
        case .createdAsc:   return "Created (old first)"
        }
    }

    /// Order two siblings of the same kind.
    func sort(_ a: VaultItem, _ b: VaultItem) -> Bool {
        switch self {
        case .nameAsc:      return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        case .nameDesc:     return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
        case .modifiedDesc: return a.modified > b.modified
        case .modifiedAsc:  return a.modified < b.modified
        case .createdDesc:  return a.created > b.created
        case .createdAsc:   return a.created < b.created
        }
    }
}

/// A *vault* is one folder on disk that the user picks. Notes are plain `.md`
/// files inside it; sub-folders nest freely. Nothing proprietary — the same
/// folder opens in Obsidian, VS Code, or iA Writer, syncs over iCloud, and
/// backs up with a copy.
struct Vault {
    let root: URL
    private let fm = FileManager.default

    /// Never shown in the sidebar.
    private static let skip: Set<String> = [
        ".DS_Store", ".obsidian", ".git", ".trash", ".swriter.json", "node_modules",
    ]

    private func hidden(_ name: String) -> Bool {
        name.hasPrefix(".") || Self.skip.contains(name)
    }

    // MARK: Tree

    /// The full vault as a tree — folders first, then notes, each group ordered
    /// by `sort`.
    func tree(sort: SortMode = .nameAsc) -> [VaultItem] { items(in: root, sort: sort) }

    private func items(in dir: URL, sort: SortMode) -> [VaultItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .creationDateKey]
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [])
        else { return [] }

        var folders: [VaultItem] = []
        var notes: [VaultItem] = []
        for url in entries {
            let name = url.lastPathComponent
            if hidden(name) { continue }
            let vals = try? url.resourceValues(forKeys: Set(keys))
            let modified = vals?.contentModificationDate ?? .distantPast
            let created = vals?.creationDate ?? .distantPast
            if vals?.isDirectory == true {
                folders.append(VaultItem(
                    id: rel(url), name: name, url: url, isDirectory: true,
                    modified: modified, created: created, children: items(in: url, sort: sort)))
            } else if name.lowercased().hasSuffix(".md") {
                notes.append(VaultItem(
                    id: rel(url), name: String(name.dropLast(3)), url: url, isDirectory: false,
                    modified: modified, created: created, children: nil))
            }
        }
        folders.sort(by: sort.sort)
        notes.sort(by: sort.sort)
        return folders + notes
    }

    // MARK: Mutations — each returns the resulting URL so the caller can select it.

    @discardableResult
    func createNote(named name: String, in dir: URL) throws -> URL {
        let base = NameUtil.slug(name.isEmpty ? "Untitled" : name)
        let url = unique(in: dir, base: base, ext: "md")
        let starter = "# \(base)\n\n"
        try starter.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func createFolder(named name: String, in dir: URL) throws -> URL {
        let base = NameUtil.slug(name.isEmpty ? "New Folder" : name)
        let url = unique(in: dir, base: base, ext: nil)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func rename(_ item: VaultItem, to newName: String) throws -> URL {
        let dir = item.url.deletingLastPathComponent()
        let base = NameUtil.slug(newName)
        let ext = item.isDirectory ? nil : "md"
        var dst = dir.appendingPathComponent(ext == nil ? base : "\(base).\(ext!)")
        if dst == item.url { return item.url }
        if fm.fileExists(atPath: dst.path) { dst = unique(in: dir, base: base, ext: ext) }
        try fm.moveItem(at: item.url, to: dst)
        return dst
    }

    func delete(_ item: VaultItem) {
        try? fm.trashItem(at: item.url, resultingItemURL: nil)
    }

    @discardableResult
    func duplicate(_ item: VaultItem) throws -> URL {
        let dir = item.url.deletingLastPathComponent()
        let ext = item.isDirectory ? nil : "md"
        let dst = unique(in: dir, base: NameUtil.slug(item.name) + " copy", ext: ext)
        try fm.copyItem(at: item.url, to: dst)
        return dst
    }

    /// Move a note or folder into `dir`, renaming on collision. Returns the new URL.
    @discardableResult
    func move(_ item: VaultItem, into dir: URL) throws -> URL {
        let name = item.url.lastPathComponent
        var dst = dir.appendingPathComponent(name)
        if fm.fileExists(atPath: dst.path) {
            let ext = item.isDirectory ? nil : "md"
            let base = item.isDirectory ? name : (name as NSString).deletingPathExtension
            dst = unique(in: dir, base: base, ext: ext)
        }
        try fm.moveItem(at: item.url, to: dst)
        return dst
    }

    /// Save image bytes into `<vault>/assets/` and return a Markdown path
    /// relative to the note's folder (so it resolves from the note).
    func saveImage(_ data: Data, ext: String, base: String, noteURL: URL) throws -> String {
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        let url = unique(in: assets, base: NameUtil.slug(base), ext: ext)
        try data.write(to: url, options: .atomic)
        return Vault.relativePath(from: noteURL.deletingLastPathComponent(), to: url)
    }

    /// A POSIX relative path from `base` to `target` (e.g. "../assets/img.png").
    static func relativePath(from base: URL, to target: URL) -> String {
        let b = base.standardizedFileURL.pathComponents
        let t = target.standardizedFileURL.pathComponents
        var i = 0
        while i < b.count, i < t.count, b[i] == t[i] { i += 1 }
        let ups = Array(repeating: "..", count: max(0, b.count - i))
        return (ups + t[i...]).joined(separator: "/")
    }

    func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func write(_ text: String, to url: URL) throws {
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // MARK: Helpers

    /// A free filename in `dir`: "Note", then "Note 2", "Note 3"…
    private func unique(in dir: URL, base: String, ext: String?) -> URL {
        func make(_ n: Int) -> URL {
            let stem = n == 1 ? base : "\(base) \(n)"
            return dir.appendingPathComponent(ext == nil ? stem : "\(stem).\(ext!)")
        }
        var n = 1
        var url = make(n)
        while fm.fileExists(atPath: url.path) { n += 1; url = make(n) }
        return url
    }

    private func rel(_ url: URL) -> String {
        let r = root.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        guard p.hasPrefix(r) else { return url.lastPathComponent }
        return String(p.dropFirst(r.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func defaultLocation() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: icloud.path, isDirectory: &isDir), isDir.boolValue {
            return icloud.appendingPathComponent("Swriter")
        }
        return home.appendingPathComponent("Documents/Swriter")
    }
}

/// Filename hygiene: keep names that survive every filesystem and sync service.
enum NameUtil {
    static func slug(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for bad in ["/", "\\", ":", "\0"] { s = s.replacingOccurrences(of: bad, with: "-") }
        if s.hasPrefix(".") { s = "_" + s.dropFirst() }
        if s.count > 120 { s = String(s.prefix(120)) }
        return s.isEmpty ? "Untitled" : s
    }
}
