import AppKit
import SwiftUI

/// A glow that breathes round the border of a row, in the colours it is given
/// and no others: a wash just inside the edge, a one-point ring and a soft bloom
/// on the ring. It fades in and out as `isActive` changes, and draws nothing, not
/// even a timer, while it is off.
///
/// It is the pulse-inner effect of border-beam (see NOTICE.md), adapted for
/// Launch: the colours come from `colors` alone, the corners are SwiftUI's
/// continuous ones, and `period` sets how slowly it breathes.
struct RowGlow: View {
    let colors: [Color]
    /// Should match the shape the glow sits on, which it traces. Continuous.
    let cornerRadius: CGFloat
    let isActive: Bool
    /// Seconds for one breath of the slowest wave, about. The preset's own pulse
    /// is 2.3 seconds; this stretches it.
    var period: TimeInterval = 40

    var body: some View {
        ZStack {
            if isActive, !colors.isEmpty {
                RowGlowLayers(colors: colors.map(GlowColor.init), cornerRadius: cornerRadius, period: period)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: isActive)
        .allowsHitTesting(false)
    }
}

/// A colour as the shader takes it.
private struct GlowColor {
    let red: Float
    let green: Float
    let blue: Float

    init(_ color: Color) {
        let srgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Float(srgb.redComponent)
        green = Float(srgb.greenComponent)
        blue = Float(srgb.blueComponent)
    }
}

/// The three layers, redrawn a few times a second. At 20 frames a second a slow
/// breath looks the same as at 120, and costs far less.
private struct RowGlowLayers: View {
    let colors: [GlowColor]
    let cornerRadius: CGFloat
    let period: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            // Reduce Motion holds it at one still frame.
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let breath = RowGlowBreath(at: time, slowdown: period / RowGlowSpec.referencePeriod)
            GeometryReader { proxy in
                ZStack {
                    RowGlowLayer(
                        shape: .wash, size: proxy.size, cornerRadius: cornerRadius,
                        blobs: RowGlowBlobs.wash(colors: colors, size: proxy.size, breath: breath),
                        opacity: RowGlowSpec.washOpacity
                    )
                    RowGlowLayer(
                        shape: .ring, size: proxy.size, cornerRadius: cornerRadius,
                        blobs: RowGlowBlobs.ring(colors: colors, size: proxy.size, breath: breath),
                        opacity: RowGlowSpec.ringOpacity
                    )
                    RowGlowLayer(
                        shape: .ring, size: proxy.size, cornerRadius: cornerRadius,
                        blobs: RowGlowBlobs.bloom(colors: colors, size: proxy.size),
                        opacity: RowGlowSpec.bloomOpacity
                    )
                    .blur(radius: RowGlowSpec.bloomBlur)
                }
            }
        }
    }
}

/// One shader pass.
private struct RowGlowLayer: View {
    enum Shape {
        /// The whole rounded rectangle, fading out towards its middle.
        case wash
        /// Just its border.
        case ring
    }

    let shape: Shape
    let size: CGSize
    let cornerRadius: CGFloat
    let blobs: [Float]
    let opacity: Double

    var body: some View {
        Rectangle()
            .fill(.white)
            .colorEffect(ShaderLibrary.default.rowGlowLayer(
                .float2(size),
                .float(cornerRadius),
                .float(RowGlowSpec.borderWidth),
                .float(shape == .wash ? 1 : 0),
                .float(shape == .wash ? RowGlowSpec.washEdgeFade : 0),
                // The wash is placed along the border so it bends round the
                // corners; the ring sits on the border already.
                .float(shape == .wash ? 1 : 0),
                .floatArray(blobs),
                .floatArray(RowGlowSpec.colorMatrix),
                .float(opacity)
            ))
    }
}

/// The blob records the shader reads: 14 floats each (see RowGlow.metal).
private enum RowGlowBlobs {
    static func wash(colors: [GlowColor], size: CGSize, breath: RowGlowBreath) -> [Float] {
        var out: [Float] = []
        for (index, blob) in RowGlowSpec.blobs.enumerated() {
            out += record(
                colors[index % colors.count], size: size, breath: breath,
                region: blob.region, corner: blob.corner, x: blob.x, y: blob.y,
                width: blob.wash.width, height: blob.wash.height, alpha: nil, fadeStop: 1
            )
        }
        // The corner patches take the next colours in the palette, and follow
        // only their corner's opacity.
        let patch = RowGlowSpec.cornerPatch
        let corners: [(RowGlowSpec.Corner, Double, Double)] = [
            (.topLeading, 0, 0), (.topTrailing, 1, 0), (.bottomLeading, 0, 1), (.bottomTrailing, 1, 1),
        ]
        for (offset, corner) in corners.enumerated() {
            out += record(
                colors[(RowGlowSpec.blobs.count + offset) % colors.count], size: size, breath: breath,
                region: 0, corner: corner.0, x: corner.1, y: corner.2,
                width: patch.size, height: patch.size, alpha: patch.alpha, fadeStop: patch.fadeStop
            )
        }
        return out
    }

    static func ring(colors: [GlowColor], size: CGSize, breath: RowGlowBreath) -> [Float] {
        var out: [Float] = []
        for (index, blob) in RowGlowSpec.blobs.enumerated() {
            out += record(
                colors[index % colors.count], size: size, breath: breath,
                region: blob.region, corner: blob.corner, x: blob.x, y: blob.y,
                width: blob.ring.width, height: blob.ring.height, alpha: nil, fadeStop: 1
            )
        }
        return out
    }

    /// The bloom holds still: its blobs don't breathe or drift, only fade out
    /// from a fixed strength.
    static func bloom(colors: [GlowColor], size: CGSize) -> [Float] {
        var out: [Float] = []
        for bloom in RowGlowSpec.blooms {
            let source = RowGlowSpec.blobs[bloom.source]
            out += encode(
                colors[bloom.source % colors.count],
                width: bloom.size.width, height: bloom.size.height,
                x: source.x * size.width, y: source.y * size.height,
                alpha: RowGlowSpec.bloomAlpha, fadeStop: 1, along: false
            )
        }
        return out
    }

    /// A breathing blob. A blob in a region follows that region's size and drift
    /// waves and its corner's opacity wave, which replaces its own alpha; a
    /// corner patch (region 0) keeps its alpha and scales it by its corner's wave.
    private static func record(
        _ color: GlowColor, size: CGSize, breath: RowGlowBreath,
        region: Int, corner: RowGlowSpec.Corner, x: Double, y: Double,
        width: Double, height: Double, alpha: Double?, fadeStop: Double
    ) -> [Float] {
        let inRegion = region > 0
        let wave = breath.opacity(of: corner)
        // Which border it hugs, so the shader knows which way "along" runs.
        let nearSide = max(min(x, 1 - x) * size.width, 0)
        let nearEnd = max(min(y, 1 - y) * size.height, 0)
        return encode(
            color,
            width: width * (inRegion ? breath.width[region] : 1),
            height: height * (inRegion ? breath.height[region] * breath.sharedHeight : 1),
            x: x * size.width + (inRegion ? breath.driftX[region] : 0),
            y: y * size.height + (inRegion ? breath.driftY[region] : 0),
            alpha: alpha.map { $0 * wave } ?? wave,
            fadeStop: fadeStop,
            along: nearSide < nearEnd
        )
    }

    private static func encode(
        _ color: GlowColor, width: Double, height: Double, x: Double, y: Double,
        alpha: Double, fadeStop: Double, along: Bool
    ) -> [Float] {
        [
            Float(width), Float(height), Float(x), Float(y),
            color.red, color.green, color.blue, Float(alpha),
            Float(fadeStop / 3), Float(alpha * 2 / 3), Float(fadeStop * 2 / 3), Float(alpha / 3), Float(fadeStop),
            along ? 1 : 0,
        ]
    }
}
