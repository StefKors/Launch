import SwiftUI

/// One row, on a single line: icon, title, and the path or kind at the right.
/// The selection is white text on the accent colour.
struct ResultRow: View {
    let item: LauncherItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(icon: item.icon, size: 24)
            Text(item.title)
                .font(.system(size: 14))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 12)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .frame(height: LauncherMetrics.rowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}
