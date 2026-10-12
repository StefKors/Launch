import AppKit

struct AppProvider: SearchProvider {
    let id = "apps"
    let triggers: [String] = []
    let includedInDefaultSearch = true
    let defaultLimit = 6

    let index: AppIndex

    func results(for query: ParsedQuery) async -> [LauncherItem] {
        index.refreshIfStale()

        // Nothing typed, nothing shown: the panel opens as just the field.
        guard !query.text.isEmpty else { return [] }

        return index.entries
            .compactMap { entry -> (AppEntry, Double)? in
                let best = [entry.name, entry.fileName]
                    .compactMap { FuzzyMatcher.score(query.text, in: $0) }
                    .max()
                guard let best else { return nil }
                return (entry, best + index.usageBoost(for: entry))
            }
            .sorted { $0.1 > $1.1 }
            .map { item(for: $0.0) }
    }

    private func item(for entry: AppEntry) -> LauncherItem {
        let url = entry.url
        return LauncherItem(
            id: "\(id):\(entry.path)",
            title: entry.name,
            subtitle: nil,
            icon: .file(path: entry.path),
            primary: .init(title: "Open") { [index] in
                index.recordLaunch(of: entry)
                Task { try? await NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
                return .done
            },
            command: .init(title: "Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return .done
            }
        )
    }
}
