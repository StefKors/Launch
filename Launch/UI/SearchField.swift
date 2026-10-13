import SwiftUI

/// The field you type in, with a magnifier and, in a mode, the badge for it.
struct SearchField: View {
    @Binding var text: String
    var mode: SearchMode?
    var placeholder: String
    var focusToken: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.secondary)
            // Badge and text share a baseline; the icon stays centred beside them.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let mode {
                    ModeBadge(name: mode.name, icon: mode.icon)
                }
                TextField(mode?.placeholder ?? placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .light))
                    .focused($isFocused)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: LauncherMetrics.searchHeight)
        .onAppear { isFocused = true }
        .onChange(of: focusToken) { isFocused = true }
    }
}
