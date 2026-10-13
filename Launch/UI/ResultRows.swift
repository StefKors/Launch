import SwiftUI

/// The rows of a result list. The selection highlight is drawn behind them by
/// `ResultList`; a row only brightens its text.
struct ResultRows: View {
    let items: [LauncherItem]
    let selectedID: LauncherItem.ID?
    let onActivate: (LauncherItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                ResultRow(item: item, isSelected: item.id == selectedID)
                    .onTapGesture { onActivate(item) }
            }
        }
    }
}
