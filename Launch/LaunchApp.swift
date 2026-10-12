import SwiftUI

@main
struct LaunchApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Launch", systemImage: "magnifyingglass") {
            Button("Show Launcher") { delegate.panelController.show() }
            Button("Welcome Guide…") { delegate.onboardingWindow.show() }
            Button("Settings…") { delegate.settingsWindow.show() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Launch") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
