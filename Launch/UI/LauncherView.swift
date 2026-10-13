import SwiftUI

enum LauncherMetrics {
    /// The card itself.
    static let width: CGFloat = 540
    static let cornerRadius: CGFloat = 22
    static let searchHeight: CGFloat = 52
    static let rowHeight: CGFloat = 36
    static let maxRows = 10
    static let listPadding: CGFloat = 8
    /// Only taken when an action fails and its error shows.
    static let errorHeight: CGFloat = 34
    static let dividerHeight: CGFloat = 1

    /// Transparent room around the card inside the window. The card's shadow is
    /// drawn into it; without it the shadow is cut off at the window's edge.
    static let shadowMargin: CGFloat = 48

    /// How long the card takes to blur in, and to blur away before its window is
    /// closed.
    static let transitionDuration: TimeInterval = 0.16

    static let cardMaxHeight = searchHeight
        + dividerHeight + CGFloat(maxRows) * rowHeight + listPadding * 2
        + dividerHeight + errorHeight

    /// The panel is always full height and transparent below the card, so
    /// resizing the list never resizes a window. On a short screen it is cut
    /// down and the list shows fewer rows (see `PanelController`).
    static let panelSize = CGSize(
        width: width + shadowMargin * 2,
        height: cardMaxHeight + shadowMargin * 2
    )
}

struct LauncherView: View {
    let model: LauncherViewModel

    var body: some View {
        VStack(spacing: 0) {
            LauncherCard(model: model)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LauncherMetrics.shadowMargin)
        .padding(.top, LauncherMetrics.shadowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.onDismiss() }
    }
}
