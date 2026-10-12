import AppKit

/// macOS keeps its own shortcuts in `com.apple.symbolichotkeys`. Spotlight's
/// is number 64 and wins over an app that registers the same keys.
enum SpotlightShortcut {
    static var isEnabled: Bool {
        // Read through CFPreferences after a sync: a cached UserDefaults
        // would miss the change when the user flips the switch while we watch.
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain)
        guard let entry = (value as? [String: Any])?["64"] as? [String: Any] else {
            // No entry means the factory default: on.
            return true
        }
        return (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) != 0)
    }

    /// Spotlight's shortcut is ⌘Space by default; people also move it, so
    /// only warn when ours is that default.
    static func conflicts(with shortcut: GlobalHotKey.Shortcut) -> Bool {
        shortcut == .commandSpace && isEnabled
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}
