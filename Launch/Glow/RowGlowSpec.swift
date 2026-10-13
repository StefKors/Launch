import Foundation

/// The numbers behind the row glow: where its blobs sit, how big they are and
/// how they breathe. Taken from the pulse-inner preset of border-beam (see
/// NOTICE.md), which the web library derives from CSS. None of its colours are
/// here: a glow is drawn in the colours it is given.
enum RowGlowSpec {
    /// Which corner's opacity wave a blob follows.
    enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    /// One blob of the glow's stack.
    struct Blob {
        /// 1 to 3: which size-and-drift wave it follows.
        let region: Int
        let corner: Corner
        /// Where its centre is, as a fraction of the row (it may sit outside).
        let x: Double
        let y: Double
        /// Radii in points, for the border ring and for the inner wash.
        let ring: (width: Double, height: Double)
        let wash: (width: Double, height: Double)
    }

    /// The blobs that make up the ring and the wash inside it. A blob takes the
    /// colour at its own index in the palette, wrapping round.
    static let blobs: [Blob] = [
        Blob(region: 1, corner: .topLeading, x: 0.33, y: -0.074, ring: (70, 40), wash: (65, 35)),
        Blob(region: 2, corner: .topLeading, x: 0.12, y: -0.05, ring: (60, 35), wash: (55, 30)),
        Blob(region: 3, corner: .bottomLeading, x: 0.021, y: 0.683, ring: (40, 70), wash: (35, 65)),
        Blob(region: 1, corner: .bottomLeading, x: 0.021, y: 0.683, ring: (20, 35), wash: (15, 30)),
        Blob(region: 2, corner: .bottomTrailing, x: 0.744, y: 1.0, ring: (180, 32), wash: (173, 28)),
        Blob(region: 3, corner: .bottomTrailing, x: 0.55, y: 1.0, ring: (85, 26), wash: (80, 22)),
        Blob(region: 1, corner: .topTrailing, x: 0.939, y: 0.0, ring: (74, 32), wash: (69, 28)),
        Blob(region: 2, corner: .topTrailing, x: 1.0, y: 0.271, ring: (26, 42), wash: (22, 38)),
        Blob(region: 3, corner: .topTrailing, x: 1.0, y: 0.271, ring: (52, 48), wash: (47, 44)),
    ]

    /// A bloom blob: the position and colour of `blobs[source]`, at its own size.
    struct Bloom {
        let source: Int
        let region: Int
        let corner: Corner
        let size: (width: Double, height: Double)
    }

    static let blooms: [Bloom] = [
        Bloom(source: 0, region: 1, corner: .topLeading, size: (84, 48)),
        Bloom(source: 1, region: 2, corner: .topLeading, size: (72, 42)),
        Bloom(source: 2, region: 3, corner: .bottomLeading, size: (48, 84)),
        Bloom(source: 4, region: 2, corner: .bottomTrailing, size: (216, 38)),
        Bloom(source: 5, region: 3, corner: .bottomTrailing, size: (102, 31)),
        Bloom(source: 6, region: 1, corner: .topTrailing, size: (89, 38)),
        Bloom(source: 8, region: 3, corner: .topTrailing, size: (62, 58)),
    ]

    /// A faint patch of light in each corner of the wash.
    static let cornerPatch = (size: 60.0, alpha: 0.18, fadeStop: 0.7)

    // MARK: Layers

    static let borderWidth = 1.0
    /// How far in from the edge the wash reaches, at most: on a short shape it
    /// reaches half the height, so it fades to nothing in the middle.
    static let washEdgeFade = 28.0
    static let washOpacity = 0.44
    static let ringOpacity = 1.0
    static let bloomOpacity = 0.66
    /// How strong the bloom's blobs start, falling to nothing at their edge.
    static let bloomAlpha = 0.76
    static let bloomBlur = 8.0

    /// The one adjustment made to the colours it is given: dimmed to this and
    /// saturated to that. Set both to 1 for the palette exactly as it comes in.
    /// (Upstream also turns the hue all the way round every 16 seconds, which
    /// would carry a palette through colours it doesn't contain: not here.)
    static let brightness = 0.75
    static let saturation = 1.2

    /// Row-major 3x3, as the shader wants it: saturate, then scale by brightness.
    static let colorMatrix: [Float] = {
        let s = saturation
        let saturate = [
            0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s,
            0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s,
            0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s,
        ]
        return saturate.map { Float($0 * brightness) }
    }()

    // MARK: Breathing

    /// One value that eases back and forth between `from` and `to`.
    struct Wave {
        let from: Double
        let to: Double
        /// Seconds for a round trip, at the preset's own speed.
        let period: Double
        let delay: Double

        /// `slowdown` stretches time: 17 makes every wave 17 times slower.
        func value(at time: Double, slowdown: Double) -> Double {
            let phase = (time - delay * slowdown) / (period * slowdown)
            let eased = (1 - cos(2 * .pi * phase)) / 2
            return from + (to - from) * eased
        }
    }

    /// What the preset's waves run at without slowing: a 2.3 second pulse.
    static let referencePeriod = 2.3

    /// Indexed by region, 1 to 3 (index 0 is unused).
    static let widthWaves = [Wave(from: 1, to: 1, period: 1, delay: 0),
                             Wave(from: 0.72, to: 1.308, period: 2.34, delay: 0),
                             Wave(from: 1.28, to: 0.762, period: 2.86, delay: 0),
                             Wave(from: 0.832, to: 1.322, period: 2.548, delay: 0)]
    static let heightWaves = [Wave(from: 1, to: 1, period: 1, delay: 0),
                              Wave(from: 1.252, to: 0.762, period: 3.276, delay: 0),
                              Wave(from: 0.776, to: 1.294, period: 2.106, delay: 0),
                              Wave(from: 1.21, to: 0.72, period: 3.64, delay: 0)]
    static let driftXWaves = [Wave(from: 0, to: 0, period: 1, delay: 0),
                              Wave(from: -33, to: 29.7, period: 3.04, delay: 0),
                              Wave(from: 26.4, to: -29.7, period: 3.572, delay: 0),
                              Wave(from: -19.8, to: 33, period: 2.755, delay: 0)]
    static let driftYWaves = [Wave(from: 0, to: 0, period: 1, delay: 0),
                              Wave(from: 18.15, to: -23.1, period: 3.04, delay: 0),
                              Wave(from: -33, to: 21.45, period: 3.572, delay: 0),
                              Wave(from: -28.05, to: 14.85, period: 2.755, delay: 0)]
    /// Every blob's height, together.
    static let sharedHeightWave = Wave(from: 0.66, to: 1.34, period: 2.4, delay: 0)

    static func opacityWave(of corner: Corner) -> Wave {
        switch corner {
        case .topLeading: Wave(from: 0.52, to: 1, period: 1.9, delay: 0)
        case .topTrailing: Wave(from: 0.52, to: 1, period: 2.508, delay: 0.532)
        case .bottomLeading: Wave(from: 0.52, to: 1, period: 1.596, delay: 1.045)
        case .bottomTrailing: Wave(from: 0.52, to: 1, period: 3.002, delay: 1.577)
        }
    }
}

/// Every wave sampled at one moment.
struct RowGlowBreath {
    /// Indexed by region, 1 to 3.
    let width: [Double]
    let height: [Double]
    let driftX: [Double]
    let driftY: [Double]
    let sharedHeight: Double
    private let opacities: [RowGlowSpec.Corner: Double]

    init(at time: Double, slowdown: Double) {
        width = RowGlowSpec.widthWaves.map { $0.value(at: time, slowdown: slowdown) }
        height = RowGlowSpec.heightWaves.map { $0.value(at: time, slowdown: slowdown) }
        driftX = RowGlowSpec.driftXWaves.map { $0.value(at: time, slowdown: slowdown) }
        driftY = RowGlowSpec.driftYWaves.map { $0.value(at: time, slowdown: slowdown) }
        sharedHeight = RowGlowSpec.sharedHeightWave.value(at: time, slowdown: slowdown)
        opacities = Dictionary(uniqueKeysWithValues: RowGlowSpec.Corner.allCases.map {
            ($0, RowGlowSpec.opacityWave(of: $0).value(at: time, slowdown: slowdown))
        })
    }

    func opacity(of corner: RowGlowSpec.Corner) -> Double {
        opacities[corner] ?? 1
    }
}
