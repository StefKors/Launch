import CoreGraphics
import Testing
@testable import Launch

struct LauncherMetricsTests {
    /// The card's shadow is drawn outside the card, inside the window. The
    /// window must be bigger than the card on the left, right, top and bottom,
    /// or the shadow is cut off there.
    @Test func theWindowLeavesRoomForTheShadowAroundTheCard() {
        let size = LauncherMetrics.panelSize
        let margin = Double(LauncherMetrics.shadowMargin)
        #expect(margin >= 24, "a soft shadow needs a generous margin")

        let extraWidth = Double(size.width) - Double(LauncherMetrics.width)
        #expect(abs(extraWidth - 2 * margin) < 0.001, "room on the left and the right")

        // Room above the card, and below it even when the list is full.
        let extraHeight = Double(size.height) - Double(LauncherMetrics.cardMaxHeight)
        #expect(abs(extraHeight - 2 * margin) < 0.001, "room above and below")
    }
}
