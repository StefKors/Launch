import AppKit

/// Borderless floating panel that takes keyboard input without activating
/// the app, so the window you were in keeps its place.
final class LauncherPanel: NSPanel {
    var onResignKey: () -> Void = {}

    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        // The SwiftUI card draws its own shadow; the panel is mostly transparent.
        hasShadow = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey()
    }
}
