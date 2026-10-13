import SwiftUI

/// One row, on a single line: icon, title, and the path or kind at the right.
/// The selection itself, glass with a glow, is drawn behind the rows by
/// `ResultRows`; the row only brightens its text.
struct ResultRow: View {
    let item: LauncherItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: LauncherMetrics.rowSpacing) {
            ItemIcon(icon: item.icon, size: LauncherMetrics.rowIconSize)
            Text(item.title)
                .font(LauncherMetrics.rowFont)
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
        .padding(.horizontal, LauncherMetrics.rowPadding)
        .frame(height: LauncherMetrics.rowHeight)
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

/// Tap a row to select it and the highlight slides there. It sits on a
/// clear-glass card like the panel's, over a colourful backdrop, because the
/// selection is glass and its glow only reads against something.
#Preview("Result rows") {
    @Previewable @State var selectedID: LauncherItem.ID? = LauncherItem.previewSamples[0].id

    ResultRows(items: LauncherItem.previewSamples, selectedID: selectedID) { selectedID = $0.id }
        .padding(LauncherMetrics.listPadding)
        .frame(width: LauncherMetrics.width)
        .glassEffect(.clear, in: .rect(cornerRadius: LauncherMetrics.cornerRadius))
        .padding(48)
        .background {
            LinearGradient(colors: [.indigo, .purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .preferredColorScheme(.dark)
}
