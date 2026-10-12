import AppKit
import SwiftUI

/// The first-run window. It floats above other windows, so it stays in view
/// while the user is in System Settings granting permissions.
final class OnboardingWindowController {
    private let model: OnboardingModel
    private let start: () -> Void
    private var window: NSWindow?

    /// `start` runs when the user finishes: it opens the launcher.
    init(hotKey: HotKeySettings, fileSearch: (any FileSearching)?, start: @escaping () -> Void) {
        model = OnboardingModel(hotKey: hotKey, fileSearch: fileSearch)
        self.start = start
        model.onFinish = { [weak self] restart in self?.finish(restart: restart) }
        model.onRestartRequested = { AppRelauncher.relaunch(showLauncher: false) }
    }

    /// `resume` keeps the saved step (launch, after a restart); otherwise the
    /// tour starts again from the welcome step.
    func show(resume: Bool = false) {
        if !resume { model.restart() }
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        // A menu-bar app isn't frontmost at launch; don't open behind others.
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func finish(restart: Bool) {
        window?.close()
        if restart {
            AppRelauncher.relaunch(showLauncher: true)
        } else {
            start()
        }
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: OnboardingView(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "Welcome to Launch"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.setContentSize(OnboardingView.size)
        window.center()
        return window
    }
}
