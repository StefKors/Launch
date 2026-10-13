import SwiftUI

/// The field you type in, with a magnifier and, in a mode, the badge for it. It
/// is laid out like a row of the list below it: the magnifier is the size of a
/// row icon and starts where they do, and the text is in the rows' font and
/// starts where their titles do.
struct SearchField: View {
    @Binding var text: String
    var mode: SearchMode?
    var placeholder: String
    var focusToken: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: LauncherMetrics.rowSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: LauncherMetrics.rowIconSize * 0.7, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: LauncherMetrics.rowIconSize, height: LauncherMetrics.rowIconSize)
            // Badge and text share a baseline; the icon stays centred beside them.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let mode {
                    ModeBadge(name: mode.name, icon: mode.icon)
                }
                TextField(mode?.placeholder ?? placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(LauncherMetrics.rowFont)
                    .focused($isFocused)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, LauncherMetrics.contentInset)
        .frame(height: LauncherMetrics.searchHeight)
        .onAppear { isFocused = true }
        .onChange(of: focusToken) { isFocused = true }
    }
}
