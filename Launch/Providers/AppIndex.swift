import Foundation

nonisolated struct AppEntry: Identifiable, Sendable {
    var id: String { path }
    let path: String
    /// Name shown in Finder (localized, without ".app").
    let name: String
    /// File name without ".app", matched too so English names keep working
    /// on a localized system.
    let fileName: String

    var url: URL { URL(fileURLWithPath: path) }
}

/// Keeps the list of installed apps. Scans a fixed set of folders (it does not
/// wait for the whole-disk file index) and rescans when one changes.
final class AppIndex {
    private(set) var entries: [AppEntry] = []

    private var lastScan = Date.distantPast
    private var scanTask: Task<Void, Never>?
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var debounce: Task<Void, Never>?
    private var launchCounts: [String: Int]

    private static let countsKey = "appLaunchCounts"
    private static let staleAfter: TimeInterval = 60

    nonisolated static let roots: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Cryptexes/App/System/Applications",
        "/System/Library/CoreServices/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    /// Apps that live outside the folders above.
    nonisolated static let extras: [String] = [
        "/System/Library/CoreServices/Finder.app",
    ]

    init() {
        launchCounts = UserDefaults.standard.dictionary(forKey: Self.countsKey) as? [String: Int] ?? [:]
        rescan()
        watchRoots()
    }

    func refreshIfStale() {
        if Date().timeIntervalSince(lastScan) > Self.staleAfter { rescan() }
    }

    func usageBoost(for entry: AppEntry) -> Double {
        let count = launchCounts[entry.path, default: 0]
        return min(100, log2(Double(count) + 1) * 20)
    }

    func recordLaunch(of entry: AppEntry) {
        launchCounts[entry.path, default: 0] += 1
        UserDefaults.standard.set(launchCounts, forKey: Self.countsKey)
    }

    private func rescan() {
        lastScan = Date()
        scanTask?.cancel()
        scanTask = Task {
            let found = await Task.detached(priority: .utility) { Self.scan() }.value
            guard !Task.isCancelled else { return }
            entries = found
        }
    }

    private func watchRoots() {
        for root in Self.roots {
            let fd = open(root, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleRescan() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
    }

    /// Installs touch a folder many times; wait for it to settle.
    private func scheduleRescan() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            rescan()
        }
    }

    nonisolated static func scan() -> [AppEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var found: [AppEntry] = []

        func add(_ url: URL) {
            let path = url.resolvingSymlinksInPath().path
            guard seen.insert(path).inserted else { return }
            let fileName = url.deletingPathExtension().lastPathComponent
            let localized = (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName
            let name = localized.map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 } ?? fileName
            found.append(AppEntry(path: path, name: name, fileName: fileName))
        }

        func scan(_ dir: URL, depth: Int) {
            let children = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for child in children {
                if child.pathExtension == "app" {
                    add(child)
                } else if depth > 0, (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // Vendor folders such as /Applications/Adobe Photoshop/.
                    scan(child, depth: depth - 1)
                }
            }
        }

        for root in roots { scan(URL(fileURLWithPath: root), depth: 1) }
        for extra in extras where fm.fileExists(atPath: extra) { add(URL(fileURLWithPath: extra)) }
        return found
    }
}
