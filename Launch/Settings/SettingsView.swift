import SwiftUI

struct SettingsView: View {
    let hotKey: HotKeySettings
    let features: FeatureSettings
    let updater: Updater
    let fileSearch: (any FileSearching)?

    @State private var indexStatus: FileSearchStatus?

    /// File search switched off, but its engine is still running: it can't be
    /// stopped, only left out at the next launch.
    private var footnotes: [Feature: String] {
        guard !features.isEnabled(.fileSearch), indexStatus != nil else { return [:] }
        return [.fileSearch: "Indexing keeps running until Launch is restarted."]
    }

    var body: some View {
        Form {
            ShortcutSection(hotKey: hotKey)

            FeaturesSection(features: features, footnotes: footnotes)

            if features.isEnabled(.fileSearch), fileSearch != nil {
                FileSearchSection(status: indexStatus)
            }

            Section("General") {
                LaunchAtLoginToggle()
            }

            UpdatesSection(updater: updater)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task { await pollIndexStatus() }
    }

    /// Refreshes while the window is open. Only a changed status is stored, so
    /// the form isn't redrawn every two seconds for nothing.
    private func pollIndexStatus() async {
        while !Task.isCancelled {
            let status = await fileSearch?.status()
            if status != indexStatus { indexStatus = status }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

/// How the file index is doing, and what is left out of it.
private struct FileSearchSection: View {
    let status: FileSearchStatus?

    private var summary: String {
        guard let status else { return "Starting…" }
        guard status.ready else { return status.progress ?? "Building…" }
        return "Ready · \(status.entries.formatted()) items"
    }

    var body: some View {
        Section("File search") {
            LabeledContent("Index") {
                Text(summary).foregroundStyle(.secondary)
            }
            NoteLabel(
                text: "Pictures, Movies, Music and Library aren't searched. macOS asks for permission every time an app opens them.",
                systemImage: "eye.slash"
            )
            if let status, !status.fullDiskAccess {
                NoteLabel(
                    text: "Without Full Disk Access, protected folders such as Desktop and Documents are skipped. Grant it, then quit and reopen Launch.",
                    systemImage: "lock.fill"
                )
                Button("Open Privacy Settings") { FullDiskAccess.openSettings() }
            }
        }
    }
}
