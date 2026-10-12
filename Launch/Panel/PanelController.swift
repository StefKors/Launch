import AppKit
import Carbon.HIToolbox
import SwiftUI

final class PanelController {
    let model: LauncherViewModel
    private let panel: LauncherPanel
    private var keyMonitor: Any?

    init(model: LauncherViewModel) {
        self.model = model
        panel = LauncherPanel(size: LauncherMetrics.panelSize)
        panel.contentView = NSHostingView(rootView: LauncherView(model: model))
        panel.onResignKey = { [weak self] in self?.hide() }
        model.onDismiss = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible else { return }
        model.reset()
        position()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        guard isVisible else { return }
        removeKeyMonitor()
        model.cancel()
        panel.orderOut(nil)
    }

    /// Top of the card sits a fifth of the way down the screen under the mouse.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = LauncherMetrics.panelSize
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - visible.height * 0.18 - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    // MARK: Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event was handled and must not reach the field.
    private func handle(_ event: NSEvent) -> Bool {
        guard panel.isKeyWindow else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let controlOnly = modifiers == .control

        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
        case kVK_DownArrow:
            model.moveSelection(1)
        case kVK_UpArrow:
            model.moveSelection(-1)
        case kVK_ANSI_N where controlOnly:
            model.moveSelection(1)
        case kVK_ANSI_P where controlOnly:
            model.moveSelection(-1)
        case kVK_Delete where modifiers.isEmpty && model.canExitMode:
            // The field is empty and a badge is showing: backspace removes it.
            if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
            model.exitMode()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            // Return confirms an input-method composition first.
            if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
            model.activate(modifiers: modifiers)
        default:
            return false
        }
        return true
    }
}
