import SwiftUI

/// One row. There is no background; the selection is brighter text and a
/// fuller icon.
///
/// Everything that changes with the selection (icon, title, subtitle) changes
/// on the same animation, so the row moves as one thing.
struct ResultRow: View {
    let item: LauncherItem
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ItemIcon(icon: item.icon, size: 22)
                .opacity(isSelected ? 1 : 0.65)
            title
            Spacer(minLength: 12)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(isSelected ? 0.6 : 0.3))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(height: LauncherMetrics.rowHeight)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(LauncherMetrics.selectionAnimation, value: isSelected)
        .animation(.smooth(duration: 0.12), value: isHovered)
    }

    /// A font's weight does not animate; it jumps while the colour next to it
    /// fades. So the title is drawn in both weights and they cross-fade. The
    /// medium one is wider, so it sets the width: sized the other way round,
    /// it would be squeezed into the regular one's width and truncated.
    private var title: some View {
        Text(item.title)
            .font(.system(size: 15, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(Color.white)
            .opacity(isSelected ? 1 : 0)
            .layoutPriority(1)
            .overlay(alignment: .leading) {
                Text(item.title)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .foregroundStyle(titleColor)
                    .opacity(isSelected ? 0 : 1)
                    // The label is read once, from the text underneath.
                    .accessibilityHidden(true)
            }
    }

    private var titleColor: Color {
        .white.opacity(isHovered ? 0.9 : 0.6)
    }
}
