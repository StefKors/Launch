import SwiftUI

/// The field you type in. No box and no icon: the text sits on the same edge
/// as the rows below it.
struct SearchField: View {
    @Binding var text: String
    var mode: SearchMode?
    var placeholder: String
    var focusToken: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        // Badge and text share a baseline.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let mode {
                ModeBadge(name: mode.name, icon: mode.icon)
            }
            TextField(mode?.placeholder ?? placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .light))
                .focused($isFocused)
                .autocorrectionDisabled()
        }
        .frame(height: LauncherMetrics.searchHeight)
        .onAppear { isFocused = true }
        .onChange(of: focusToken) { isFocused = true }
    }
}
