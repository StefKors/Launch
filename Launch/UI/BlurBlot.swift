import SwiftUI

/// What the launcher sits on: a pool of blur over whatever is below the
/// window, strongest in the middle and thinning out to nothing on every side,
/// so there is no edge to see.
///
/// The blur is a true progressive one (see `ProgressiveBlur`). If macOS no
/// longer allows that, two materials with different reach stand in for it.
///
/// It is `Equatable` on its one input, so SwiftUI only touches it when the
/// list's height changes.
struct BlurBlot: View, Equatable {
    /// How tall the pool should be: it follows the list.
    let height: CGFloat
    /// The blur grows from nothing as the launcher appears and back out as it goes.
    let isPresented: Bool

    /// Measured outward from the content, in each margin the effect stays full
    /// for the first `core` of it, then fades out over the next `fade`. What is
    /// left of the margin is untouched, so the window's edge never cuts through
    /// any of it.
    ///
    /// `overlap` moves where the fade starts that far in over the content, on
    /// every side, without moving where it ends: a negative margin. The content
    /// then sits partly in the fade, not wholly in full blur.
    private static func profile(core: CGFloat, fade: CGFloat, overlap: CGFloat = 0) -> BlurProfile {
        func insets(_ scale: (CGFloat) -> CGFloat) -> EdgeInsets {
            EdgeInsets(
                top: scale(LauncherMetrics.blurMarginTop),
                leading: scale(LauncherMetrics.blurMarginX),
                bottom: scale(LauncherMetrics.blurMarginBottom),
                trailing: scale(LauncherMetrics.blurMarginX)
            )
        }
        return BlurProfile(inset: insets { $0 * (1 - core) + overlap }, falloff: insets { $0 * fade + overlap })
    }

    /// The blur reaches further out than the tint, so what the tint darkens is
    /// always already out of focus.
    private static let spec = ProgressiveBlur.Spec(
        radius: 10,
        blur: profile(core: 0, fade: 0.95, overlap: 60),
        tint: profile(core: 0, fade: 0.7),
        tintOpacity: 0.16,
        restingHeight: LauncherMetrics.collapsedBlurHeight,
        height: LauncherMetrics.collapsedBlurHeight,
        presence: 0
    )

    private var spec: ProgressiveBlur.Spec {
        var spec = Self.spec
        spec.height = height
        spec.presence = isPresented ? 1 : 0
        return spec
    }

    var body: some View {
        if ProgressiveBlur.isSupported {
            ProgressiveBlur(spec: spec)
        } else {
            // Two materials with different reach.
            ZStack {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Rectangle().fill(.thickMaterial)
                        .mask { pool(inset: 0.14, softness: 0.1) }
                }
                .mask { pool(inset: 0.04, softness: 0.1) }
                Rectangle().fill(Color.black.opacity(0.34))
                    .mask { pool(inset: 0.1, softness: 0.12) }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.smooth(duration: 0.25), value: height)
            .opacity(isPresented ? 1 : 0)
            .animation(.smooth(duration: LauncherMetrics.transitionDuration), value: isPresented)
        }
    }

    /// A rounded rectangle with a blurred edge. `inset` and `softness` are
    /// fractions of the view's shorter side, so the pool keeps its shape whether
    /// it is just the field or a full list.
    private func pool(inset: CGFloat, softness: CGFloat) -> some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height)
            RoundedRectangle(cornerRadius: unit * 0.16, style: .continuous)
                .fill(.black)
                .padding(unit * inset)
                .blur(radius: unit * softness)
        }
    }
}
