import AppKit
import SwiftUI

/// The settings window. A menu-bar app has no main window, and SwiftUI's
/// Settings scene is unreliable to open from one, so this owns a plain window.
final class SettingsWindowController {
    private let hotKey: HotKeySettings
    private let fileSearch: (any FileSearching)?
    private var window: NSWindow?

    init(hotKey: HotKeySettings, fileSearch: (any FileSearching)?) {
        self.hotKey = hotKey
        self.fileSearch = fileSearch
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(hotKey: hotKey, fileSearch: fileSearch))
        let window = NSWindow(contentViewController: controller)
        window.title = "Launch Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
