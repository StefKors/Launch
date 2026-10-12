import SwiftUI

/// A feature's icon, name and one-line description, with its on/off switch.
struct FeatureToggleRow: View {
    let icon: LauncherItem.Icon
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                ItemIcon(icon: icon, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
