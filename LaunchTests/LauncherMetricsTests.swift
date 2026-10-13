import CoreGraphics
import Testing
@testable import Launch

struct LauncherMetricsTests {
    /// The card's shadow is drawn into the transparent margin of the window. The
    /// window must be bigger than the card on every side, or the shadow is cut
    /// off at the window's edge.
    @Test func theWindowLeavesRoomForTheShadow() {
        let size = LauncherMetrics.panelSize
        let margin = Double(LauncherMetrics.shadowMargin)
        #expect(margin >= 40, "a soft shadow needs a generous margin")

        let extraWidth = Double(size.width) - Double(LauncherMetrics.width)
        #expect(abs(extraWidth - 2 * margin) < 0.001, "room on the left and the right")

        // Room above the card, and below it even when the list is full.
        let extraHeight = Double(size.height) - Double(LauncherMetrics.cardMaxHeight)
        #expect(abs(extraHeight - 2 * margin) < 0.001, "room above and below")
    }

    @Test func theTallestCardHoldsAFullListAndAnError() {
        let list = CGFloat(LauncherMetrics.maxRows) * LauncherMetrics.rowHeight + LauncherMetrics.listInset * 2
        let tallest = LauncherMetrics.searchHeight + list + LauncherMetrics.errorHeight + 2 * LauncherMetrics.dividerHeight
        #expect(LauncherMetrics.cardMaxHeight == tallest)
    }
}
