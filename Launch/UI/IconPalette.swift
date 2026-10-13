import AppKit
import SwiftUI

/// The colours an icon is made of, for lighting up a row in them: Safari gives
/// blues and red, Slack its four, Terminal greys and green.
///
/// The icon is shrunk to a small bitmap and its colourful pixels are sorted into
/// twelve hue buckets, weighted by how saturated and bright they are. The
/// biggest buckets become the palette, followed by a lighter and a deeper shade
/// of the biggest, so a one-colour icon still gets a range. An icon with no
/// colour at all (a plain document, a grey app) gets greys.
enum IconPalette {
    /// What a row with no icon image to read (a symbol) is lit with.
    static let neutral: [Color] = [Color(white: 0.92), Color(white: 0.7), Color(white: 0.55)]

    private final class Entry {
        let colors: [Color]
        init(_ colors: [Color]) { self.colors = colors }
    }

    private static let cache = NSCache<NSString, Entry>()

    static func colors(for icon: LauncherItem.Icon) -> [Color] {
        switch icon {
        case .file(let path):
            if let cached = cache.object(forKey: path as NSString) { return cached.colors }
            let colors = colors(of: IconCache.shared.icon(forFile: path))
            cache.setObject(Entry(colors), forKey: path as NSString)
            return colors
        case .tile(_, let tint):
            return shades(of: NSColor(tint.color))
        case .symbol:
            return neutral
        }
    }

    static func colors(of image: NSImage) -> [Color] {
        let side = 24
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let data = context.data
        else { return neutral }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let bucketCount = 12
        var weight = [Double](repeating: 0, count: bucketCount)
        var sum = [SIMD3<Double>](repeating: .zero, count: bucketCount)
        var neutralWeight = 0.0
        var neutralSum = SIMD3<Double>.zero

        for index in 0..<(side * side) {
            let alpha = Double(pixels[index * 4 + 3]) / 255
            guard alpha > 0.6 else { continue }
            // The bitmap is premultiplied.
            let rgb = SIMD3(Double(pixels[index * 4]), Double(pixels[index * 4 + 1]), Double(pixels[index * 4 + 2])) / 255 / alpha
            let high = rgb.max(), low = rgb.min()
            guard high > 0.3 else { continue }
            let saturation = (high - low) / high
            if saturation > 0.28 {
                let bucket = Int(hue(of: rgb, high: high, low: low) / 30) % bucketCount
                let w = saturation * high
                weight[bucket] += w
                sum[bucket] += rgb * w
            } else {
                neutralWeight += high
                neutralSum += rgb * high
            }
        }

        let total = weight.reduce(0, +)
        let ranked = weight.indices
            .filter { total > 0 && weight[$0] >= total * 0.08 }
            .sorted { weight[$0] > weight[$1] }
            .prefix(3)
        guard let first = ranked.first else {
            // Nothing colourful: the icon's own grey, or white.
            guard neutralWeight > 0 else { return neutral }
            let grey = neutralSum / neutralWeight
            return [color(grey), Color(white: 0.95), Color(white: 0.6)]
        }

        let main = sum[first] / weight[first]
        let rest = ranked.dropFirst().map { color(sum[$0] / weight[$0]) }
        return [color(main)] + rest + shades(of: NSColor(srgbRed: main.x, green: main.y, blue: main.z, alpha: 1)).dropFirst()
    }

    /// The colour, a lighter shade and a deeper one.
    private static func shades(of color: NSColor) -> [Color] {
        let base = color.usingColorSpace(.sRGB) ?? color
        let light = base.blended(withFraction: 0.45, of: .white) ?? base
        let deep = base.blended(withFraction: 0.3, of: .black) ?? base
        return [Color(nsColor: base), Color(nsColor: light), Color(nsColor: deep)]
    }

    private static func color(_ rgb: SIMD3<Double>) -> Color {
        Color(.sRGB, red: rgb.x, green: rgb.y, blue: rgb.z)
    }

    /// Degrees, 0 to 360.
    private static func hue(of rgb: SIMD3<Double>, high: Double, low: Double) -> Double {
        let delta = high - low
        guard delta > 0 else { return 0 }
        let degrees: Double
        if high == rgb.x {
            degrees = 60 * ((rgb.y - rgb.z) / delta).truncatingRemainder(dividingBy: 6)
        } else if high == rgb.y {
            degrees = 60 * ((rgb.z - rgb.x) / delta + 2)
        } else {
            degrees = 60 * ((rgb.x - rgb.y) / delta + 4)
        }
        return degrees < 0 ? degrees + 360 : degrees
    }
}
