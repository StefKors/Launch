import SwiftUI

/// The "Open Launch" shortcut recorder with its conflict warnings.
struct ShortcutSection: View {
    let hotKey: HotKeySettings

    var body: some View {
        Section("Shortcut") {
            LabeledContent("Open Launch") {
                ShortcutRecorder(settings: hotKey)
            }
            if hotKey.registrationFailed {
                NoteLabel(text: "Another app is using this shortcut. Pick a different one.", systemImage: "exclamationmark.triangle.fill")
            }
            if SpotlightShortcut.conflicts(with: hotKey.shortcut) {
                NoteLabel(
                    text: "Spotlight still uses ⌘Space, so it opens instead of Launch. Turn off “Show Spotlight search” in Keyboard Shortcuts → Spotlight.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                Button("Open Keyboard Settings") { SpotlightShortcut.openKeyboardSettings() }
            }
        }
    }
}
