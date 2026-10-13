import AppKit
import SwiftUI

struct PermissionsStepView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(
                title: "Two things to check",
                subtitle: "These live in System Settings. Launch notices when you change them."
            )
            VStack(spacing: 12) {
                ShortcutPermissionRow(model: model)
                FullDiskAccessPermissionRow(model: model)
            }
        }
    }
}

private struct ShortcutPermissionRow: View {
    let model: OnboardingModel

    private var shortcut: String { model.hotKey.shortcut.displayString }

    private var detail: String {
        model.spotlightConflict
            ? "Spotlight is using ⌘Space, so it opens instead of Launch. Turn off “Show Spotlight search” in Keyboard Shortcuts → Spotlight."
            : "\(shortcut) is free: nothing else is using it."
    }

    var body: some View {
        PermissionRow(
            state: model.spotlightConflict ? .needed : .granted,
            title: "Shortcut: \(shortcut)",
            detail: detail
        ) {
            Button("Open Keyboard Settings") { SpotlightShortcut.openKeyboardSettings() }
        }
    }
}

private struct FullDiskAccessPermissionRow: View {
    let model: OnboardingModel

    private var state: PermissionState {
        if model.needsRestartForFullDiskAccess { return .needed }
        return model.fullDiskAccessGranted ? .granted : .optional
    }

    private var detail: String {
        if model.needsRestartForFullDiskAccess {
            return "Granted. Restart Launch so file search can see Desktop, Documents, Downloads and iCloud Drive. This tour reopens right here."
        }
        if model.fullDiskAccessGranted {
            return "Granted. File search can see Desktop, Documents, Downloads and iCloud Drive."
        }
        return "Lets file search include Desktop, Documents, Downloads and iCloud Drive. Without it Launch skips those folders. If Launch isn't listed, click + and add it."
    }

    var body: some View {
        PermissionRow(state: state, title: "Full Disk Access", detail: detail) {
            if model.needsRestartForFullDiskAccess {
                // The tour reopens at this step after the restart.
                Button("Restart Launch") { model.requestRestart() }
            } else {
                Button("Open Privacy Settings") { FullDiskAccess.openSettings() }
                Button("Show Launch in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
            }
        }
    }
}
