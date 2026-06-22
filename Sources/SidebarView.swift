import SwiftUI
import AppKit

/// The vault browser, modeled on MarkView: a workspace switcher, header tools
/// (new note/folder, search, sort, expand/collapse), and a tree with inline
/// rename, double-click-to-rename, and a full right-click menu.
struct SidebarView: View {
    @EnvironmentObject var store: AppStore

    @State private var renamingID: String?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    @State private var searchVisible = false
    @FocusState private var searchFocused: Bool

    @State private var wsRenamingID: String?
    @State private var wsRenameText = ""

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceSwitcher(beginRename: beginRenameWorkspace,
                              addExisting: addExistingVault,
                              createNew: createNewVault)
            headerTools
            if searchVisible { searchField }
            Divider()
            tree
        }
        .frame(minWidth: 200)
        .alert("Rename Vault", isPresented: Binding(
            get: { wsRenamingID != nil }, set: { if !$0 { wsRenamingID = nil } })) {
            TextField("Name", text: $wsRenameText)
            Button("Rename") {
                if let id = wsRenamingID { store.renameWorkspace(id, to: wsRenameText) }
                wsRenamingID = nil
            }
            Button("Cancel", role: .cancel) { wsRenamingID = nil }
        }
    }

    // MARK: Header tools

    private var headerTools: some View {
        HStack(spacing: 2) {
            tool("square.and.pencil", "New Note") {
                if let id = store.newNote() { beginRename(id: id, name: "Untitled") }
            }
            tool("folder.badge.plus", "New Folder") {
                if let id = store.newFolder() { beginRename(id: id, name: "New Folder") }
            }
            Spacer()
            tool("magnifyingglass", searchVisible ? "Hide Search" : "Search") {
                searchVisible.toggle()
                if searchVisible { DispatchQueue.main.async { searchFocused = true } }
                else { store.searchQuery = "" }
            }
            Menu {
                ForEach(SortMode.allCases) { m in
                    Button { store.sortMode = m } label: {
                        if store.sortMode == m { Label(m.title, systemImage: "checkmark") }
                        else { Text(m.title) }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30).help("Sort")

            tool(store.anyExpanded ? "arrow.down.right.and.arrow.up.left"
                                   : "arrow.up.left.and.arrow.down.right",
                 store.anyExpanded ? "Collapse All" : "Expand All") {
                if store.anyExpanded { store.collapseAll() } else { store.expandAll() }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
    }

    private func tool(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 24, height: 22) }
            .buttonStyle(.borderless).help(help)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField("Find note or folder…", text: $store.searchQuery)
                .textFieldStyle(.plain).focused($searchFocused)
                .onExitCommand { store.searchQuery = ""; searchVisible = false }
            if !store.searchQuery.isEmpty {
                Button { store.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    // MARK: Tree

    @ViewBuilder private var tree: some View {
        let rows = store.visibleRows()
        if rows.isEmpty {
            emptyState
        } else {
            List {
                ForEach(rows) { row in
                    rowView(row)
                        .listRowInsets(EdgeInsets(top: 1, leading: CGFloat(8 + row.depth * 14),
                                                  bottom: 1, trailing: 6))
                        .listRowBackground(rowBackground(row.item))
                }
                Color.clear.frame(height: 16)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contextMenu { rootMenu }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 24)
        }
    }

    private func rowView(_ row: TreeRow) -> some View {
        let item = row.item
        return HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.secondary)
                .rotationEffect(.degrees((store.isExpanded(item.id) || store.isSearching) && item.isDirectory ? 90 : 0))
                .frame(width: 12)
                .opacity(item.isDirectory ? 1 : 0)
            Image(systemName: item.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(item.isDirectory ? store.theme.accentColor : Color.secondary)
                .frame(width: 16)
            if renamingID == item.id {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .onChange(of: renameFocused) { focused in
                        if !focused, renamingID == item.id { commitRename() }
                    }
            } else {
                Text(item.name).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRename(id: item.id, name: item.name) }
        .onTapGesture { primaryTap(item) }
        .contextMenu { itemMenu(item) }
    }

    private func rowBackground(_ item: VaultItem) -> some View {
        (store.currentURL == item.url ? store.theme.accentColor.opacity(0.16) : Color.clear)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: store.isSearching ? "magnifyingglass" : "doc.text")
                .font(.largeTitle).foregroundStyle(.tertiary)
            Text(store.isSearching ? "No matches" : "No notes yet").foregroundStyle(.secondary)
            if !store.isSearching {
                Button("New Note") { if let id = store.newNote() { beginRename(id: id, name: "Untitled") } }
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .contextMenu { rootMenu }
    }

    // MARK: Context menus

    @ViewBuilder private func itemMenu(_ item: VaultItem) -> some View {
        Button("New Note") { if let id = store.newNote(in: item) { beginRename(id: id, name: "Untitled") } }
        Button("New Folder") { if let id = store.newFolder(in: item) { beginRename(id: id, name: "New Folder") } }
        Divider()
        Button("Rename") { beginRename(id: item.id, name: item.name) }
        Button("Duplicate") { if let id = store.duplicate(item) { beginRename(id: id, name: item.name + " copy") } }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        Divider()
        Button("Move to Trash", role: .destructive) { store.delete(item) }
    }

    @ViewBuilder private var rootMenu: some View {
        Button("New Note") { if let id = store.newNote() { beginRename(id: id, name: "Untitled") } }
        Button("New Folder") { if let id = store.newFolder() { beginRename(id: id, name: "New Folder") } }
    }

    // MARK: Actions

    private func primaryTap(_ item: VaultItem) {
        if item.isDirectory { store.toggleExpand(item.id) }
        else { store.openNote(at: item.url) }
    }

    private func beginRename(id: String, name: String) {
        renameText = name
        renamingID = id
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename() {
        guard let id = renamingID else { return }
        renamingID = nil
        if let item = store.findItem(id) { store.rename(item, to: renameText) }
    }

    private func cancelRename() { renamingID = nil }

    private func beginRenameWorkspace(_ id: String) {
        wsRenameText = store.workspaces.first { $0.id == id }?.name ?? ""
        wsRenamingID = id
    }

    private func addExistingVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        panel.title = "Open an Existing Vault Folder"
        if panel.runModal() == .OK, let url = panel.url { store.addVault(at: url, create: false) }
    }

    private func createNewVault() {
        let panel = NSSavePanel()
        panel.title = "Create a New Vault"
        panel.prompt = "Create Vault"
        panel.nameFieldStringValue = "New Vault"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { store.addVault(at: url, create: true) }
    }
}

/// The vault dropdown in the sidebar header — switch, add, rename, or forget a
/// vault. Forgetting only drops the pointer; it never deletes files.
private struct WorkspaceSwitcher: View {
    @EnvironmentObject var store: AppStore
    let beginRename: (String) -> Void
    let addExisting: () -> Void
    let createNew: () -> Void

    private var activeName: String {
        store.workspaces.first { $0.id == store.activeWorkspaceID }?.name
            ?? store.vaultURL?.lastPathComponent ?? "Vault"
    }

    var body: some View {
        Menu {
            ForEach(store.workspaces) { ws in
                Button { store.switchWorkspace(ws.id) } label: {
                    if ws.id == store.activeWorkspaceID {
                        Label(ws.name, systemImage: "checkmark")
                    } else {
                        Text(ws.name)
                    }
                }
            }
            Divider()
            Button("Open Vault…") { addExisting() }
            Button("New Vault…") { createNew() }
            if let active = store.activeWorkspaceID {
                Divider()
                Button("Rename This Vault…") { beginRename(active) }
                Button("Reveal in Finder") { store.revealInFinder() }
                Button("Remove This Vault from List") { store.removeWorkspace(active) }
                    .disabled(store.workspaces.count <= 1)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "books.vertical.fill").foregroundStyle(store.theme.accentColor)
                Text(activeName).font(.headline).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
    }
}
