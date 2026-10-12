import SwiftUI

struct SettingsView: View {
    let hotKey: HotKeySettings
    let fileSearch: (any FileSearching)?

    @State private var indexStatus: FileSearchStatus?

    var body: some View {
        Form {
            ShortcutSection(hotKey: hotKey)

            Section("General") {
                LaunchAtLoginToggle()
            }

            if fileSearch != nil {
                fileSearchSection
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // Refresh while the window is open.
            while !Task.isCancelled {
                indexStatus = await fileSearch?.status()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var fileSearchSection: some View {
        Section("File search") {
            LabeledContent("Index") {
                Text(indexSummary).foregroundStyle(.secondary)
            }
            NoteLabel(
                text: "Pictures, Movies, Music and Library aren't searched. macOS asks for permission every time an app opens them.",
                systemImage: "eye.slash"
            )
            if let status = indexStatus, !status.fullDiskAccess {
                NoteLabel(
                    text: "Without Full Disk Access, protected folders such as Desktop and Documents are skipped. Grant it, then quit and reopen Launch.",
                    systemImage: "lock.fill"
                )
                Button("Open Privacy Settings") { FullDiskAccess.openSettings() }
            }
        }
    }

    private var indexSummary: String {
        guard let status = indexStatus else { return "Starting…" }
        guard status.ready else { return status.progress ?? "Building…" }
        return "Ready · \(status.entries.formatted()) items"
    }
}
