import ServiceManagement
import SwiftUI

/// "Open at login", including the case where macOS wants the user to approve
/// the login item in System Settings first.
struct LaunchAtLoginToggle: View {
    /// Nil until the view has appeared. The status comes from the system, and a
    /// view's initial state is built every time its parent redraws, so it is
    /// read once in `.task` instead.
    @State private var status: SMAppService.Status?
    @State private var errorMessage: String?

    private var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var body: some View {
        Toggle("Open at login", isOn: Binding(get: { isEnabled }, set: setEnabled))
            .task { status = SMAppService.mainApp.status }
        if status == .requiresApproval {
            NoteLabel(text: "macOS needs your approval: switch Launch on in Login Items.", systemImage: "exclamationmark.triangle.fill")
            Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
        }
        if let errorMessage {
            NoteLabel(text: errorMessage, systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func setEnabled(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't change the login item: \(error.localizedDescription)"
        }
        status = SMAppService.mainApp.status
    }
}
