import CoreGraphics
import Testing
@testable import Launch

struct LauncherMetricsTests {
    /// The blur fades out over the transparent margin of the window. The
    /// window must be bigger than the content on every side, or the fade is
    /// cut off at the window's edge.
    @Test func theWindowLeavesRoomForTheBlurToFadeOut() {
        let size = LauncherMetrics.panelSize
        #expect(LauncherMetrics.blurMarginX >= 100, "a soft edge needs a generous margin")

        let extraWidth = Double(size.width) - Double(LauncherMetrics.contentWidth)
        #expect(abs(extraWidth - 2 * Double(LauncherMetrics.blurMarginX)) < 0.001, "room on the left and the right")

        // Room above the content, and below it even when the list is full.
        let extraHeight = Double(size.height) - Double(LauncherMetrics.contentMaxHeight)
        let margins = Double(LauncherMetrics.blurMarginTop + LauncherMetrics.blurMarginBottom)
        #expect(abs(extraHeight - margins) < 0.001, "room above and below")
    }
}

struct BlurProfileTests {
    private let size = CGSize(width: 400, height: 300)
    private let profile = BlurProfile(
        inset: .init(top: 60, leading: 80, bottom: 90, trailing: 80),
        falloff: .init(top: 40, leading: 60, bottom: 70, trailing: 60)
    )

    @Test func theCoreIsBlurredInFull() {
        #expect(profile.strength(x: 200, y: 150, in: size) == 1)
        #expect(profile.strength(x: 80, y: 60, in: size) == 1, "the core's edge")
    }

    @Test func blurIsGoneBeforeTheEdgeOfTheView() {
        // Each side's falloff ends at or inside the view's edge.
        #expect(profile.strength(x: 0, y: 150, in: size) == 0)
        #expect(profile.strength(x: 400, y: 150, in: size) == 0)
        #expect(profile.strength(x: 200, y: 0, in: size) == 0)
        #expect(profile.strength(x: 200, y: 300, in: size) == 0)
        #expect(profile.strength(x: 0, y: 0, in: size) == 0, "corners too")
    }

    @Test func blurFadesWithoutAJump() {
        let strengths = stride(from: 80.0, through: 20.0, by: -1).map { profile.strength(x: $0, y: 150, in: size) }
        #expect(strengths == strengths.sorted(by: >), "never stronger further out")
        let biggestStep = zip(strengths, strengths.dropFirst()).map { abs($0 - $1) }.max() ?? 0
        #expect(biggestStep < 0.08, "no step in the ramp")
    }

    @Test func aShortPoolLeavesTheRestOfTheViewAlone() {
        var short = profile
        short.height = 150
        #expect(short.strength(x: 200, y: 60, in: size) == 1)
        #expect(short.strength(x: 200, y: 150, in: size) == 0, "the pool ends at its height")
        #expect(short.strength(x: 200, y: 290, in: size) == 0, "nothing below it")
        #expect(profile.strength(x: 200, y: 200, in: size) == 1, "without a height the pool is the whole view")
    }

    @Test func overlappingFadesFromBothSidesStillMeet() {
        // A pool so short that the top fade and the bottom fade overlap: it
        // peaks where they cross, below full strength, and is not zero.
        var tiny = profile
        tiny.height = 140
        let peak = tiny.strength(x: 200, y: 70, in: size)
        #expect(peak > 0 && peak < 1)
        #expect(peak >= tiny.strength(x: 200, y: 20, in: size), "strongest in the middle")
        #expect(peak >= tiny.strength(x: 200, y: 120, in: size))
    }

    @Test func aSideWithNoFalloffDoesNotDivideByZero() {
        let hard = BlurProfile(inset: .init(top: 10, leading: 10, bottom: 10, trailing: 10), falloff: .init())
        let value = hard.strength(x: 0, y: 0, in: size)
        #expect(value == 1 && value.isFinite)
    }
}
