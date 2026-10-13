import Carbon.HIToolbox
import SwiftUI

struct ReadyStepView: View {
    let model: OnboardingModel

    /// The shortcut as separate caps ("⌘", "Space").
    private var shortcutKeys: [KeyCap.Key] {
        let shortcut = model.hotKey.shortcut
        var keys: [KeyCap.Key] = []
        if shortcut.modifiers & UInt32(controlKey) != 0 { keys.append(.text("⌃")) }
        if shortcut.modifiers & UInt32(optionKey) != 0 { keys.append(.option) }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { keys.append(.text("⇧")) }
        if shortcut.modifiers & UInt32(cmdKey) != 0 { keys.append(.command) }
        keys.append(.text(shortcut.label))
        return keys
    }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            StepHeader(title: "You're all set", subtitle: "Press your shortcut anywhere to open Launch.")

            HStack(spacing: 4) {
                ForEach(shortcutKeys, id: \.self) { KeyCap(key: $0) }
            }

            VStack(alignment: .leading, spacing: 8) {
                if model.spotlightConflict {
                    NoteLabel(text: "Spotlight still has ⌘Space. Launch won't open from it until Spotlight's shortcut is off.", systemImage: "exclamationmark.triangle.fill")
                    Button("Open Keyboard Settings") { SpotlightShortcut.openKeyboardSettings() }
                }
                if model.needsRestartForFullDiskAccess {
                    NoteLabel(text: "Full Disk Access is on. Launch restarts once so file search can see the protected folders.", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}
