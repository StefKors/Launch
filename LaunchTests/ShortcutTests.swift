import AppKit
import Carbon.HIToolbox
import Testing
@testable import Launch

struct ShortcutTests {
    @Test func defaultIsCommandSpace() {
        #expect(GlobalHotKey.Shortcut.commandSpace.displayString == "⌘Space")
    }

    @Test func modifiersShowInSystemOrder() throws {
        let shortcut = try #require(GlobalHotKey.Shortcut.from(
            keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .shift, .option, .control], characters: "k"
        ))
        #expect(shortcut.displayString == "⌃⌥⇧⌘K")
    }

    @Test func aKeyWithoutCommandControlOrOptionIsRejected() {
        #expect(GlobalHotKey.Shortcut.from(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [], characters: "k") == nil)
        // Shift alone would take over capital letters.
        #expect(GlobalHotKey.Shortcut.from(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.shift], characters: "K") == nil)
    }

    @Test func specialKeysUseTheirNames() throws {
        let shortcut = try #require(GlobalHotKey.Shortcut.from(keyCode: UInt16(kVK_Space), modifierFlags: [.option], characters: " "))
        #expect(shortcut.displayString == "⌥Space")
        #expect(shortcut != .commandSpace)
    }

    @Test func survivesEncodingForUserDefaults() throws {
        let data = try JSONEncoder().encode(GlobalHotKey.Shortcut.commandSpace)
        #expect(try JSONDecoder().decode(GlobalHotKey.Shortcut.self, from: data) == .commandSpace)
    }

    @Test func spotlightWarningOnlyAppliesToCommandSpace() throws {
        let other = try #require(GlobalHotKey.Shortcut.from(keyCode: UInt16(kVK_Space), modifierFlags: [.option], characters: " "))
        #expect(!SpotlightShortcut.conflicts(with: other))
    }
}
