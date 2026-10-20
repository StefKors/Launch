import SwiftUI

@main
struct LaunchApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    /// The menu bar is AppKit's (`MenuBarController`), so this scene only
    /// satisfies `App`. It shows no window.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
