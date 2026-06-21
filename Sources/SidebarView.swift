import SwiftUI
import AppKit

/// The vault browser: a folder/note tree with new, rename, delete, and reveal.
struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @State private var renaming: VaultItem?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.tree.isEmpty {
                emptyState
            } else {
                List {
                    OutlineGroup(store.tree, children: \.children) { item in
                        row(item)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 200, idealWidth: 250)
        .alert("Rename", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let item = renaming { store.rename(item, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "books.vertical.fill").foregroundStyle(store.theme.accentColor)
            Text(store.vaultURL?.lastPathComponent ?? "Vault")
                .font(.headline).lineLimit(1).truncationMode(.middle)
            Spacer()
            Menu {
                Button("New Note") { store.newNote() }
                Button("New Folder") { store.newFolder() }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton).frame(width: 26)

            Menu {
                Button("Reveal Vault in Finder") { store.revealInFinder() }
                Button("Refresh") { store.refreshTree() }
                Divider()
                Button("Open Different Vault…") { changeVault() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).frame(width: 26)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.tertiary)
            Text("No notes yet").foregroundStyle(.secondary)
            Button("New Note") { store.newNote() }.buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ item: VaultItem) -> some View {
        let isOpen = store.currentURL == item.url
        return HStack(spacing: 6) {
            Image(systemName: item.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(item.isDirectory ? store.theme.accentColor : Color.secondary)
                .frame(width: 16)
            Text(item.name).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { if !item.isDirectory { store.openNote(at: item.url) } }
        .listRowBackground(isOpen ? store.theme.accentColor.opacity(0.16) : Color.clear)
        .contextMenu {
            if item.isDirectory {
                Button("New Note Here") { store.newNote(in: item) }
                Button("New Folder Here") { store.newFolder(in: item) }
                Divider()
            }
            Button("Rename…") { renameText = item.name; renaming = item }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Move to Trash", role: .destructive) { store.delete(item) }
        }
    }

    private func changeVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        if panel.runModal() == .OK, let url = panel.url { store.openVault(at: url) }
    }
}
