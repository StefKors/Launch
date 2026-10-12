import AppKit

/// File and folder search, backed by fsearch.
///
/// A plain query only gets a "File Search" row; choosing it switches the
/// launcher into file mode (the "Files" badge), where the real results appear.
struct FileProvider: SearchProvider {
    let id = "files"
    let triggers = ["f", "file", "/"]
    let modeInfo: ModeInfo? = ModeInfo(name: "Files", placeholder: "Search files", icon: .file(path: Self.finderPath))
    private static let finderPath = "/System/Library/CoreServices/Finder.app"
    let includedInDefaultSearch = true
    let defaultLimit = 1

    let engine: any FileSearching

    private static let resultLimit = 30
    private static let minModeRowQueryLength = 2

    func results(for query: ParsedQuery) async -> [LauncherItem] {
        let text = query.text
        guard !text.isEmpty else { return [] }

        // Get the cores clocked up before the first file search.
        engine.keepWarm()

        guard query.isExclusive else {
            return text.count >= Self.minModeRowQueryLength ? [modeItem(for: text)] : []
        }

        switch await engine.search(text, limit: Self.resultLimit) {
        case .hits(let hits):
            return hits.map(item)
        case .indexing(let progress):
            return [statusItem(title: "Indexing files…", subtitle: progress, symbol: "hourglass")]
        case .failed(let message):
            return [statusItem(title: "File search unavailable", subtitle: message, symbol: "exclamationmark.triangle")]
        case .superseded:
            return []
        }
    }

    private func modeItem(for text: String) -> LauncherItem {
        LauncherItem(
            id: "\(id):mode",
            title: "File Search",
            subtitle: "Search files for “\(text)”",
            icon: .file(path: Self.finderPath),
            primary: .init(title: "Search Files") { [id] in .enterMode(providerID: id, query: text) }
        )
    }

    private func item(for hit: FileHit) -> LauncherItem {
        let url = hit.url
        let parent = url.deletingLastPathComponent().path
        return LauncherItem(
            id: "\(id):\(hit.path)",
            title: url.lastPathComponent,
            subtitle: (parent as NSString).abbreviatingWithTildeInPath,
            icon: .file(path: hit.path),
            primary: .init(title: "Open") {
                NSWorkspace.shared.open(url)
                return .done
            },
            command: .init(title: "Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return .done
            },
            option: .init(title: "Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hit.path, forType: .string)
                return .done
            }
        )
    }

    /// A row that explains why there are no files to show. Return keeps the
    /// launcher open.
    private func statusItem(title: String, subtitle: String?, symbol: String) -> LauncherItem {
        LauncherItem(
            id: "\(id):status",
            title: title,
            subtitle: subtitle,
            icon: .symbol(symbol),
            primary: .init(title: "Dismiss") { .failed(subtitle ?? title) }
        )
    }
}
