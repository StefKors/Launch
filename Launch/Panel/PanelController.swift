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
        let hostingView = NSHostingView(rootView: LauncherView(model: model))
        // The panel is sized by `position()`, never by what the view asks for.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.onResignKey = { [weak self] in self?.hide() }
        model.onDismiss = { [weak self] in self?.hide() }
    }

    /// Whether the launcher is meant to be showing. The window outlives this by
    /// `LauncherMetrics.transitionDuration` while it blurs away.
    private(set) var isShown = false
    private var pendingOrderOut: DispatchWorkItem?

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        // Shown again while still blurring away: keep that window.
        pendingOrderOut?.cancel()
        pendingOrderOut = nil
        panel.ignoresMouseEvents = false

        model.isPresented = false
        model.reset()
        position()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        // One turn later, so the window is up before it animates in.
        DispatchQueue.main.async { [weak self] in
            guard let self, isShown else { return }
            model.isPresented = true
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        removeKeyMonitor()
        model.cancel()
        model.isPresented = false
        // Whatever is under the launcher gets the clicks while it fades.
        panel.ignoresMouseEvents = true

        let order = DispatchWorkItem { [weak self] in
            guard let self, !isShown else { return }
            panel.orderOut(nil)
            pendingOrderOut = nil
        }
        pendingOrderOut = order
        DispatchQueue.main.asyncAfter(deadline: .now() + LauncherMetrics.transitionDuration, execute: order)
    }

    /// The content (not the window, which has a transparent margin for the
    /// blur to fade out in) starts a seventh of the way down the screen under
    /// the mouse. On a short screen the window is cut down to fit, and the
    /// list shows fewer rows.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var size = LauncherMetrics.panelSize
        size.height = min(size.height, visible.height)
        let top = visible.maxY - visible.height * 0.14 + LauncherMetrics.blurMarginTop
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: max(visible.minY, top - size.height)
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
