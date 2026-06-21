import SwiftUI
import AppKit

/// "About Swriter" — app identity plus the GitHub-release update flow, modeled
/// on Kanpan's About/update panel.
struct AboutView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let releasesURL = URL(string: "https://github.com/enderphan94/swriter/releases")!

    var body: some View {
        VStack(spacing: 14) {
            AppGlyph(size: 72)
            VStack(spacing: 3) {
                Text("Swriter").font(.system(size: 22, weight: .bold))
                Text("Version \(Updater.current)").font(.callout).foregroundStyle(.secondary)
            }
            Text("A calm Markdown writer for notes and books.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider().padding(.vertical, 2)

            updateSection.frame(minHeight: 64)

            Divider().padding(.vertical, 2)

            HStack {
                Button("View all releases") { NSWorkspace.shared.open(releasesURL) }
                    .buttonStyle(.link)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("Your writing stays local as Markdown. No account, no tracking.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            if case .idle = store.updateState { store.checkForUpdates() }
        }
    }

    @ViewBuilder
    private var updateSection: some View {
        switch store.updateState {
        case .idle:
            Button("Check for Updates") { store.checkForUpdates() }
                .buttonStyle(.bordered)

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…").foregroundStyle(.secondary)
            }

        case .upToDate:
            VStack(spacing: 8) {
                Label("You're up to date.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Check Again") { store.checkForUpdates() }
                    .buttonStyle(.bordered).controlSize(.small)
            }

        case .available(let info):
            VStack(spacing: 8) {
                Label("Swriter \(info.latest) is available", systemImage: "arrow.down.circle.fill")
                    .font(.headline).foregroundStyle(Color.accentColor)
                Text("You have \(info.current).").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Update Now") { store.applyUpdate(info) }
                        .buttonStyle(.borderedProminent)
                    if let r = info.releaseURL {
                        Button("Release Notes") { NSWorkspace.shared.open(r) }
                            .buttonStyle(.link)
                    }
                }
            }

        case .downloading:
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading and installing…").foregroundStyle(.secondary)
                Text("Swriter will quit and reopen on its own in a moment.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

        case .failed(let message):
            VStack(spacing: 6) {
                Label("Couldn't update", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(3)
                HStack(spacing: 10) {
                    Button("Try Again") { store.checkForUpdates() }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("Download in Browser") { NSWorkspace.shared.open(releasesURL) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }
}
