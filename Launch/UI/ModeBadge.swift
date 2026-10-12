import SwiftUI

/// The pill in the search field that stands for the current mode.
///
/// Its first-text-baseline is the label's, so the pill lines up with the text
/// typed next to it. The icon is centred on the label's x-height instead of
/// sitting on the baseline.
struct ModeBadge: View {
    let name: String
    var icon: LauncherItem.Icon?

    private static let iconSize: CGFloat = 16

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let icon {
                ItemIcon(icon: icon, size: Self.iconSize)
                    // The icon's "baseline" is the point 5pt below its centre,
                    // which is where the label's x-height middle sits.
                    .alignmentGuide(.firstTextBaseline) { $0.height / 2 + 5 }
            }
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.leading, icon == nil ? 9 : 6)
        .padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
