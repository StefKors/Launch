import SwiftUI

/// "Open  [↩]": what a key combination does, as the label followed by one cap
/// per key.
struct ShortcutHint: View {
    let title: String
    let keys: [KeyCap.Key]
    var isPrimary = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(isPrimary ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { KeyCap(key: $0) }
            }
        }
    }
}
