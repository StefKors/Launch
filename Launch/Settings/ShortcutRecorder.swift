import AppKit
import SwiftUI

/// A button that shows the shortcut and records a new one on click.
struct ShortcutRecorder: View {
    let settings: HotKeySettings

    @State private var monitor: Any?

    var body: some View {
        Button(settings.isRecording ? "Press shortcut…" : settings.shortcut.displayString) {
            settings.isRecording ? stop() : start()
        }
        .buttonStyle(.bordered)
        .onDisappear { stop() }
    }

    private func start() {
        settings.setRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { handle(event) }
            return consumed ? nil : event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        settings.setRecording(false)
    }

    /// Escape cancels; a key with ⌘, ⌃ or ⌥ held is taken.
    private func handle(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
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
