import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut. Uses the Carbon hot key API, which needs no
/// Accessibility permission and works for an unsandboxed app.
///
/// Spotlight owns Command-Space by default; the system lets only one
/// registration win, so Spotlight's shortcut has to be turned off first.
nonisolated final class GlobalHotKey {
    struct Shortcut: Equatable, Codable {
        var keyCode: UInt32
        /// Carbon modifier mask (`cmdKey`, `optionKey`, ...).
        var modifiers: UInt32
        /// What the key is called on screen ("Space", "K").
        var label: String

        static let commandSpace = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey), label: "Space")

        /// "⌃⌥⇧⌘" in the order macOS shows them, then the key.
        var displayString: String {
            var s = ""
            if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
            return s + label
        }

        /// The shortcut for a key press, or nil when it has no ⌘, ⌃ or ⌥ and
        /// would swallow ordinary typing.
        static func from(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, characters: String?) -> Shortcut? {
            var mask: UInt32 = 0
            if modifierFlags.contains(.command) { mask |= UInt32(cmdKey) }
            if modifierFlags.contains(.option) { mask |= UInt32(optionKey) }
            if modifierFlags.contains(.control) { mask |= UInt32(controlKey) }
            guard mask != 0 else { return nil }
            if modifierFlags.contains(.shift) { mask |= UInt32(shiftKey) }
            let label = specialKeys[Int(keyCode)] ?? characters?.uppercased() ?? "Key \(keyCode)"
            return Shortcut(keyCode: UInt32(keyCode), modifiers: mask, label: label)
        }

        private static let specialKeys: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    private static let signature: OSType = 0x4C4E_4348 // 'LNCH'

    /// Returns nil when the system refuses the registration.
    init?(_ shortcut: Shortcut, action: @escaping @MainActor () -> Void) {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Application-target events arrive on the main thread.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else { return nil }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let registered = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registered == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
