import SwiftUI

struct ResultRow: View {
    let item: LauncherItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(icon: item.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 15))
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
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
