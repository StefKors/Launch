import SwiftUI

/// The version, the automatic-check switch and a "Check Now" button.
struct UpdatesSection: View {
    let updater: Updater

    var body: some View {
        Section("Updates") {
            LabeledContent("Version") {
                Text(Updater.versionDescription).foregroundStyle(.secondary)
            }
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.setAutomaticallyChecks($0) }
            ))
            Button("Check Now") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
