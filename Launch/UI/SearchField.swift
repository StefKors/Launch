import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var mode: SearchMode?
    var focusToken: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
            // Badge and text share a baseline; the icon stays centred beside them.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let mode {
                    ModeBadge(name: mode.name, icon: mode.icon)
                }
                TextField(mode?.placeholder ?? "Search apps, files, processes", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .light))
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
