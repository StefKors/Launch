import SwiftUI

/// The last action's error, under the list. Nothing else lives down here: the
/// launcher shows no shortcut hints.
struct ActionErrorBar: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(.orange)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: LauncherMetrics.footerHeight)
    }
}
