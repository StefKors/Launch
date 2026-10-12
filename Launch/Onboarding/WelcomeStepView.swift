import AppKit
import SwiftUI

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 22) {
            // The app's own icon, as macOS draws it (from AppIcon.icon).
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
            StepHeader(title: "Welcome to Launch", subtitle: "One box for opening apps, finding files and quitting processes.")
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(symbol: "square.grid.2x2", title: "Open apps", detail: "Type a few letters or the initials: “sysset” finds System Settings.")
                FeatureRow(symbol: "doc.text.magnifyingglass", title: "Find files", detail: "Pick File Search under any query to search everything on your Mac.")
                FeatureRow(symbol: "xmark.circle", title: "Quit processes", detail: "Type “kill ” and a name to quit it, or force-quit with ⌥↩.")
            }
            .padding(.horizontal, 8)
        }
    }
}
