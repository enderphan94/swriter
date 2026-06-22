import SwiftUI
import AppKit

@main
struct SwriterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: AppStore

    init() {
        let s = AppStore()
        s.bootstrap()
        AppDelegate.store = s          // so we can flush on quit
        _store = StateObject(wrappedValue: s)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 880, minHeight: 600)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { menus }
    }

    @CommandsBuilder private var menus: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Swriter") { store.showAbout = true }
            Button("Check for Updates…") {
                store.showAbout = true
                store.checkForUpdates()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Note") { store.newNote() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!store.hasVault)
            Button("New Folder…") { store.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!store.hasVault)
        }

        CommandGroup(after: .saveItem) {
            Button("Save") { store.flush() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!store.hasDocument)
            Divider()
            Button("Export to PDF (A5)…") { store.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!store.hasDocument)
        }

        // Markdown formatting — operates on the focused editor.
        CommandMenu("Format") {
            Button("Bold") { store.format(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { store.format(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button("Strikethrough") { store.format(.strikethrough) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { store.format(.code) }
                .keyboardShortcut("e", modifiers: .command)
            Divider()
            Button("Heading 1") { store.format(.heading(1)) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Heading 2") { store.format(.heading(2)) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Heading 3") { store.format(.heading(3)) }
                .keyboardShortcut("3", modifiers: .command)
            Divider()
            Button("Bulleted List") { store.format(.bulletList) }
                .keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Numbered List") { store.format(.numberList) }
                .keyboardShortcut("7", modifiers: [.command, .shift])
            Button("Quote") { store.format(.quote) }
                .keyboardShortcut("'", modifiers: [.command, .shift])
            Divider()
            Button("Link…") { store.format(.link) }
                .keyboardShortcut("k", modifiers: .command)
            Button("Insert Image…") { store.importImage() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Insert Table") { store.format(.table) }
            Button("Code Block") { store.format(.codeBlock) }
            Button("Horizontal Rule") { store.format(.horizontalRule) }
        }

        CommandGroup(after: .toolbar) {
            Button("Switch View Mode") { store.cycleMode() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!store.hasDocument)
            Button("Writing Mode") { store.mode = .write }.disabled(!store.hasDocument)
            Button("Split Mode") { store.mode = .split }.disabled(!store.hasDocument)
            Button("Reading Mode") { store.mode = .read }.disabled(!store.hasDocument)
            Divider()

            Button(store.focusMode ? "Turn Off Focus" : "Focus Mode") {
                store.focusMode.toggle()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button(store.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                store.sidebarVisible.toggle()
            }
            .keyboardShortcut("\\", modifiers: .command)

            Divider()
            Button("Bigger Text") { store.fontSize = min(32, store.fontSize + 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Text") { store.fontSize = max(11, store.fontSize - 1) }
                .keyboardShortcut("-", modifiers: .command)

            Menu("Theme") {
                ForEach(WriterTheme.allCases) { t in
                    Button(t.title) { store.theme = t }
                }
            }
        }
    }
}

/// Flushes unsaved edits when the app quits, and quits when the window closes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var store: AppStore?
    func applicationWillTerminate(_ notification: Notification) { AppDelegate.store?.flush() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if store.hasVault {
                MainView()
            } else {
                WelcomeView()
            }
        }
        .preferredColorScheme(store.theme.colorScheme)
        .sheet(isPresented: $store.showAbout) {
            AboutView().environmentObject(store)
        }
        .alert("Update Available", isPresented: Binding(
            get: { store.pendingUpdate != nil },
            set: { if !$0 { store.pendingUpdate = nil } })) {
            Button("Update Now") { if let u = store.pendingUpdate { store.applyUpdate(u) } }
            if let r = store.pendingUpdate?.releaseURL {
                Button("Release Notes") { NSWorkspace.shared.open(r) }
            }
            Button("Later", role: .cancel) { store.pendingUpdate = nil }
        } message: {
            if let u = store.pendingUpdate {
                Text("Swriter \(u.latest) is available — you have \(u.current). Update now? Swriter will restart to finish.")
            }
        }
        .task { store.checkForUpdatesOnLaunch() }
    }
}
