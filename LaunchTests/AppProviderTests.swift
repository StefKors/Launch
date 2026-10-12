import Foundation
import Testing
@testable import Launch

@MainActor
struct AppProviderTests {
    @Test func scanFindsFinderAndSystemApps() {
        let entries = AppIndex.scan()
        #expect(entries.contains { $0.name == "Finder" })
        #expect(entries.contains { $0.path.hasPrefix("/System/Applications/") })
        // Each bundle once, even if it is reachable from two folders.
        #expect(Set(entries.map(\.path)).count == entries.count)
    }

    @Test func findsAnAppByNameAndByInitials() async throws {
        let index = AppIndex()
        let provider = AppProvider(index: index)
        try await waitUntilScanned(index)

        let finder = await provider.results(for: ParsedQuery(raw: "finder", text: "finder", trigger: nil))
        #expect(finder.first?.title == "Finder")
        // Just the name, vertically centred: no folder line.
        #expect(finder.first?.subtitle == nil)
        #expect(finder.first?.primary.title == "Open")
        #expect(finder.first?.command?.title == "Reveal in Finder")

        // System Settings is "sysset" for a Spotlight user.
        let settings = await provider.results(for: ParsedQuery(raw: "sysset", text: "sysset", trigger: nil))
        #expect(settings.contains { $0.title == "System Settings" })
    }

    @Test func emptyFieldShowsNoHistory() async throws {
        let index = AppIndex()
        try await waitUntilScanned(index)
        // Even for an app launched before: the panel opens as just the input.
        index.recordLaunch(of: try #require(index.entries.first))
        let rows = await AppProvider(index: index).results(for: ParsedQuery(raw: "", text: "", trigger: nil))
        #expect(rows.isEmpty)
    }

    @Test func nothingMatchesGibberish() async throws {
        let index = AppIndex()
        try await waitUntilScanned(index)
        let rows = await AppProvider(index: index).results(for: ParsedQuery(raw: "qqzzxx", text: "qqzzxx", trigger: nil))
        #expect(rows.isEmpty)
    }

    private func waitUntilScanned(_ index: AppIndex) async throws {
        for _ in 0..<100 where index.entries.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(!index.entries.isEmpty, "app scan never finished")
    }
}
