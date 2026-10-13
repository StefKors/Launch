import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that shows the shortcut and records a new one on click.
struct ShortcutRecorder: View {
    let settings: HotKeySettings

    @State private var monitor: LocalKeyMonitor?

    var body: some View {
        Button(settings.isRecording ? "Press shortcut…" : settings.shortcut.displayString) {
            settings.isRecording ? stop() : start()
        }
        .buttonStyle(.bordered)
        .onDisappear { stop() }
    }

    private func start() {
        settings.setRecording(true)
        let monitor = LocalKeyMonitor { event in handle(event) }
        monitor.install()
        self.monitor = monitor
    }

    private func stop() {
        monitor?.remove()
        monitor = nil
        settings.setRecording(false)
    }

    /// Escape cancels; a key with ⌘, ⌃ or ⌥ held is taken.
    private func handle(_ event: NSEvent) -> Bool {
        if Int(event.keyCode) == kVK_Escape {
            stop()
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let shortcut = GlobalHotKey.Shortcut.from(
            keyCode: event.keyCode, modifierFlags: flags, characters: event.charactersIgnoringModifiers
        ) else {
            NSSound.beep()
            return true
        }
        stop()
        settings.setShortcut(shortcut)
        return true
    }
}
