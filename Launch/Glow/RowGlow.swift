import AppKit
import SwiftUI

/// A glow that breathes round the border of a row, in the colours it is given
/// and no others: a wash just inside the edge, a one-point ring and a soft bloom
/// on the ring. It fades in and out as `isActive` changes, and draws nothing, not
/// even a timer, while it is off.
///
/// When `colors` change, the glow blends from the old colours to the new ones,
/// and its breathing carries straight on: it keeps one clock and never restarts.
/// So one glow can follow a selection from row to row.
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

    @State private var palette: GlowPalette

    init(colors: [Color], cornerRadius: CGFloat, isActive: Bool, period: TimeInterval = 40) {
        self.colors = colors
        self.cornerRadius = cornerRadius
        self.isActive = isActive
        self.period = period
        _palette = State(initialValue: GlowPalette(colors.map(GlowColor.init)))
    }

    var body: some View {
        ZStack {
            if isActive, !colors.isEmpty {
                RowGlowLayers(palette: palette, cornerRadius: cornerRadius, period: period)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: isActive)
        .allowsHitTesting(false)
        .onChange(of: colors) {
            palette.retarget(to: colors.map(GlowColor.init), at: Date())
        }
    }
}

/// A colour as the shader takes it.
struct GlowColor {
    var red: Float
    var green: Float
    var blue: Float

    init(_ color: Color) {
        let srgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Float(srgb.redComponent)
        green = Float(srgb.greenComponent)
        blue = Float(srgb.blueComponent)
    }

    private init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    func mixed(with other: GlowColor, _ amount: Float) -> GlowColor {
        GlowColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }
}

/// The glow's colours, and a blend from the previous set to them.
struct GlowPalette {
    /// Seconds a change of colours takes to blend: about as long as the
    /// highlight takes to slide to the new row.
    static let blendDuration: TimeInterval = 0.15

    private var from: [GlowColor]
    private var to: [GlowColor]
    private var changedAt = Date.distantPast

    init(_ colors: [GlowColor]) {
        from = colors
        to = colors
    }

    /// Blends from whatever is showing now, so a change in the middle of another
    /// carries on from where that had got to.
    mutating func retarget(to colors: [GlowColor], at date: Date) {
        guard !colors.isEmpty else { return }
        from = self.colors(at: date)
        to = colors
        changedAt = date
    }

    /// The colours showing at `date`.
    func colors(at date: Date) -> [GlowColor] {
        guard !from.isEmpty, !to.isEmpty else { return to.isEmpty ? from : to }
        let progress = min(max(date.timeIntervalSince(changedAt) / Self.blendDuration, 0), 1)
        if progress >= 1 { return to }
        // Eased, so it starts and ends gently.
        let eased = Float(progress * progress * (3 - 2 * progress))
        return (0..<max(from.count, to.count)).map { from[$0 % from.count].mixed(with: to[$0 % to.count], eased) }
    }
}

/// The three layers, redrawn a few times a second. At 20 frames a second a slow
/// breath looks the same as at 120, and costs far less.
private struct RowGlowLayers: View {
    let palette: GlowPalette
    let cornerRadius: CGFloat
    let period: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            // The waves run on the clock, not on when the glow appeared, so they
            // carry on unbroken however often it is moved or shown again.
            // Reduce Motion holds them at one still frame.
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let breath = RowGlowBreath(at: time, slowdown: period / RowGlowSpec.referencePeriod)
            let colors = palette.colors(at: timeline.date)
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

    /// How far in the wash reaches: at most half the height, so that it is
    /// exactly nothing in the middle of a short row.
    private var washFade: Double {
        min(RowGlowSpec.washEdgeFade, size.height / 2)
    }

    var body: some View {
        Rectangle()
            .fill(.white)
            .colorEffect(ShaderLibrary.default.rowGlowLayer(
                .float2(size),
                .float(cornerRadius),
                .float(RowGlowSpec.borderWidth),
                .float(shape == .wash ? 1 : 0),
                .float(shape == .wash ? washFade : 0),
                .floatArray(blobs),
                .floatArray(RowGlowSpec.colorMatrix),
                .float(opacity)
            ))
    }
}

/// The blob records the shader reads: 13 floats each (see RowGlow.metal).
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
                alpha: RowGlowSpec.bloomAlpha, fadeStop: 1
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
        return encode(
            color,
            width: width * (inRegion ? breath.width[region] : 1),
            height: height * (inRegion ? breath.height[region] * breath.sharedHeight : 1),
            x: x * size.width + (inRegion ? breath.driftX[region] : 0),
            y: y * size.height + (inRegion ? breath.driftY[region] : 0),
            alpha: alpha.map { $0 * wave } ?? wave,
            fadeStop: fadeStop
        )
    }

    private static func encode(
        _ color: GlowColor, width: Double, height: Double, x: Double, y: Double,
        alpha: Double, fadeStop: Double
    ) -> [Float] {
        [
            Float(width), Float(height), Float(x), Float(y),
            color.red, color.green, color.blue, Float(alpha),
            Float(fadeStop / 3), Float(alpha * 2 / 3), Float(fadeStop * 2 / 3), Float(alpha / 3), Float(fadeStop),
        ]
    }
}
