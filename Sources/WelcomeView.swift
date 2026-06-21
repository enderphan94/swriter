import SwiftUI
import AppKit

/// First run: choose where the vault lives. A vault is just a folder of `.md`
/// files, so the user can point at an existing notes folder or make a new one.
struct WelcomeView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            AppGlyph(size: 96)
            VStack(spacing: 6) {
                Text("Swriter").font(.system(size: 30, weight: .bold))
                Text("Write and read like a book — in plain Markdown you own.")
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button(action: createVault) {
                    Label("Create a New Vault", systemImage: "plus.rectangle.on.folder")
                        .frame(maxWidth: 240)
                }
                .controlSize(.large).buttonStyle(.borderedProminent)

                Button(action: openVault) {
                    Label("Open an Existing Folder", systemImage: "folder")
                        .frame(maxWidth: 240)
                }
                .controlSize(.large).buttonStyle(.bordered)
            }

            Text("A vault is a folder on disk. Your notes are `.md` files you can\nalso open in Obsidian, VS Code, or iA Writer, and sync with iCloud.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(store.theme.bg)
    }

    private func createVault() {
        let panel = NSSavePanel()
        panel.title = "Create a New Vault"
        panel.prompt = "Create Vault"
        panel.nameFieldStringValue = "Swriter"
        panel.directoryURL = Vault.defaultLocation().deletingLastPathComponent()
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            store.createVault(at: url)
        }
    }

    private func openVault() {
        let panel = NSOpenPanel()
        panel.title = "Open a Vault Folder"
        panel.prompt = "Open Vault"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
        if panel.runModal() == .OK, let url = panel.url {
            store.openVault(at: url)
        }
    }
}
