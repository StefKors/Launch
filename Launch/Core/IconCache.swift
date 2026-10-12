import AppKit

final class IconCache {
    static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()

    func icon(forFile path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}
