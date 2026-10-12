import SwiftUI

/// Footer showing what each modifier does for the selected row, or the last
/// action's error.
struct ActionHintBar: View {
    let item: LauncherItem?
    let errorMessage: String?
    /// Backspace on the empty field leaves the current mode.
    var canGoBack = false

    var body: some View {
        HStack(spacing: 12) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if let item {
                ShortcutHint(title: item.primary.title, keys: [.return], isPrimary: true)
                if let command = item.command {
                    separator
                    ShortcutHint(title: command.title, keys: [.command, .return])
                }
                if let option = item.option {
                    separator
                    ShortcutHint(title: option.title, keys: [.option, .return])
                }
            }
            Spacer(minLength: 0)
            if canGoBack { ShortcutHint(title: "All results", keys: [.delete]) }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: LauncherMetrics.footerHeight)
    }

    private var separator: some View {
        Divider().frame(height: 14)
    }
}
