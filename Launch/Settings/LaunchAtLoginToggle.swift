import ServiceManagement
import SwiftUI

/// "Open at login", including the case where macOS wants the user to approve
/// the login item in System Settings first.
struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var errorMessage: String?

    var body: some View {
        Toggle("Open at login", isOn: binding)
        if status == .requiresApproval {
            NoteLabel(text: "macOS needs your approval: switch Launch on in Login Items.", systemImage: "exclamationmark.triangle.fill")
            Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
        }
        if let errorMessage {
            NoteLabel(text: errorMessage, systemImage: "exclamationmark.triangle.fill")
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { status == .enabled || status == .requiresApproval },
            set: { enable in
                do {
                    if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    errorMessage = nil
                } catch {
                    errorMessage = "Couldn't change the login item: \(error.localizedDescription)"
                }
                status = SMAppService.mainApp.status
            }
        )
    }
}
