import SwiftUI

/// The rows of a result list, with the selection highlight behind them.
///
/// The highlight is one view that moves to the selected row, rather than a mark
/// on each row. Its glow therefore keeps breathing as the selection changes, and
/// blends to the colours of the new row's icon on the way.
struct ResultRows: View {
    /// How the highlight slides from one row to the next: quick, so it keeps up
    /// with someone holding the arrow key, and without a bounce.
    private static let slide = Animation.snappy(duration: 0.12, extraBounce: 0)

    let items: [LauncherItem]
    let selectedID: LauncherItem.ID?
    let onActivate: (LauncherItem) -> Void

    private var selectedIndex: Int? {
        items.firstIndex { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                ResultRow(item: item, isSelected: item.id == selectedID)
                    .id(item.id)
                    .onTapGesture { onActivate(item) }
            }
        }
        .background(alignment: .top) {
            if let index = selectedIndex {
                RowSelection(colors: IconPalette.colors(for: items[index].icon))
                    .frame(height: LauncherMetrics.rowHeight)
                    .offset(y: CGFloat(index) * LauncherMetrics.rowHeight)
                    .animation(Self.slide, value: index)
                    .transition(.opacity)
            }
        }
    }
}
