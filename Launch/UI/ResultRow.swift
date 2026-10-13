import SwiftUI

/// One row, on a single line: icon, title, and the path or kind at the right.
///
/// The selected row is a piece of regular glass on the card's clear glass, with
/// a glow breathing round its border in the colours of its own icon, so slowly
/// that it only reads as a shimmer.
struct ResultRow: View {
    /// How slowly the glow breathes; see `RowGlow`.
    private static let glowPeriod: TimeInterval = 40
    /// The glass and the glow round their corners alike: continuous, 12 pt.
    private static let cornerRadius: CGFloat = 12
    private static let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

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
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary.opacity(0.7)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: LauncherMetrics.rowHeight)
        // On top of the glass. Only the selected row draws anything.
        .background {
            RowGlow(
                colors: IconPalette.colors(for: item.icon),
                cornerRadius: Self.cornerRadius,
                isActive: isSelected,
                period: Self.glowPeriod
            )
        }
        .compositingGroup()
        .glassEffect(isSelected ? .regular : .identity, in: Self.shape)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

private extension LauncherItem {
    /// One of each kind of row the launcher shows, and one with a title and a
    /// path too long to fit.
    static let previewSamples: [LauncherItem] = [
        sample("notes", "Notes", icon: .file(path: "/System/Applications/Notes.app")),
        sample("terminal", "Terminal", icon: .file(path: "/System/Applications/Utilities/Terminal.app")),
        sample("file", "Quarterly Report.xlsx", subtitle: "~/Documents/Finance", icon: .file(path: #filePath)),
        sample("process", "Google Chrome Helper", subtitle: "PID 4821 · /Applications/Google Chrome.app", icon: .tile(symbol: "cpu.fill", tint: .red)),
        sample(
            "long", "A file with a name that keeps going well past the end of the row.pdf",
            subtitle: "~/Documents/Projects/Archive/2026/Reports/Quarterly/Finance/Drafts",
            icon: .symbol("doc.text")
        ),
    ]

    private static func sample(_ id: String, _ title: String, subtitle: String? = nil, icon: Icon) -> LauncherItem {
        LauncherItem(id: id, title: title, subtitle: subtitle, icon: icon, primary: .init(title: "Open") { .done })
    }
}

/// Tap a row to select it. It sits on a clear-glass card like the panel's, over
/// a colourful backdrop, because the selected row is glass and its glow only
/// reads against something.
#Preview("Result rows") {
    @Previewable @State var selectedID: LauncherItem.ID? = LauncherItem.previewSamples[0].id

    VStack(spacing: 0) {
        ForEach(LauncherItem.previewSamples) { item in
            ResultRow(item: item, isSelected: item.id == selectedID)
                .onTapGesture { selectedID = item.id }
        }
    }
    .padding(LauncherMetrics.listPadding)
    .frame(width: LauncherMetrics.width)
    .glassEffect(.clear, in: .rect(cornerRadius: LauncherMetrics.cornerRadius))
    .padding(48)
//    .background {
//        LinearGradient(colors: [.indigo, .purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
//    }
    .preferredColorScheme(.dark)
}
