import Foundation
import Testing
@testable import Launch

private func isolatedDefaults() -> UserDefaults {
    let name = "FeatureTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
struct FeatureSettingsTests {
    @Test func everythingStartsOn() {
        let settings = FeatureSettings(defaults: isolatedDefaults())
        for feature in Feature.allCases { #expect(settings.isEnabled(feature), "\(feature)") }
    }

    @Test func switchesArePersisted() {
        let defaults = isolatedDefaults()
        let first = FeatureSettings(defaults: defaults)
        first.setEnabled(.kill, false)

        let second = FeatureSettings(defaults: defaults)
        #expect(!second.isEnabled(.kill))
        #expect(second.isEnabled(.fileSearch), "other features are untouched")
    }

    @Test func onChangeFiresOnlyForRealChanges() {
        let settings = FeatureSettings(defaults: isolatedDefaults())
        var changes: [String] = []
        settings.onChange = { feature, on in changes.append("\(feature.rawValue)=\(on)") }

        settings.setEnabled(.kill, true)    // already on
        settings.setEnabled(.kill, false)
        settings.setEnabled(.kill, false)   // no change
        settings.setEnabled(.fileSearch, false)
        settings.setEnabled(.fileSearch, true)
        #expect(changes == ["kill=false", "fileSearch=false", "fileSearch=true"])
    }

    @Test func providersAreLookedUpByTheirId() {
        let settings = FeatureSettings(defaults: isolatedDefaults())
        settings.setEnabled(.kill, false)
        #expect(!settings.isEnabled(providerID: "processes"))
        #expect(settings.isEnabled(providerID: "files"))
        // Apps are not a switchable feature.
        #expect(settings.isEnabled(providerID: "apps"))
    }
}

@MainActor
struct FeatureWiringTests {
    private struct NoEngine: FileSearching {
        func search(_ query: String, limit: Int) async -> FileSearchOutcome { .hits([]) }
        func status() async -> FileSearchStatus? { nil }
        func keepWarm() {}
    }

    /// A feature must point at the provider that implements it, with the
    /// same icon, or its settings row and its badge would disagree.
    @Test func eachFeatureMatchesItsProvider() throws {
        let providers: [any SearchProvider] = [FileProvider(engine: NoEngine()), ProcessProvider()]
        for feature in Feature.allCases {
            let provider = try #require(providers.first { $0.id == feature.providerID }, "\(feature) has no provider")
            #expect(provider.modeInfo?.icon == feature.icon, "\(feature) icon")
            #expect(!provider.triggers.isEmpty)
        }
    }

    @Test func killHasARedCpuTile() {
        #expect(Feature.kill.icon == .tile(symbol: "cpu.fill", tint: .red))
    }

    @Test func fileSearchKeepsTheFinderIcon() {
        #expect(Feature.fileSearch.icon == .file(path: "/System/Library/CoreServices/Finder.app"))
    }

    @Test func aSwitchedOffFeatureLeavesTheRouter() {
        let settings = FeatureSettings(defaults: isolatedDefaults())
        let all: [any SearchProvider] = [AppProvider(index: AppIndex()), FileProvider(engine: NoEngine()), ProcessProvider()]
        let router = QueryRouter { all.filter { settings.isEnabled(providerID: $0.id) } }

        #expect(router.detectMode(in: "kill chrome")?.mode.name == "Kill")
        #expect(router.defaultPlaceholder == "Search apps, files, processes")

        settings.setEnabled(.kill, false)
        // "kill " is now just text for an app search, not a mode.
        #expect(router.detectMode(in: "kill chrome") == nil)
        #expect(router.parse("kill chrome").providers.map(\.id) == ["apps", "files"])
        #expect(router.defaultPlaceholder == "Search apps, files")

        settings.setEnabled(.fileSearch, false)
        #expect(router.detectMode(in: "f cv") == nil)
        #expect(router.parse("cv.pdf").providers.map(\.id) == ["apps"])
        #expect(router.defaultPlaceholder == "Search apps")

        settings.setEnabled(.kill, true)
        #expect(router.detectMode(in: "kill chrome") != nil, "switching back on works without a restart")
    }

    @Test func aFixedRouterStillWorks() {
        let router = QueryRouter(providers: [ProcessProvider()])
        #expect(router.providers.count == 1)
        #expect(router.defaultPlaceholder == "Search apps, processes")
    }
}

/// A fake engine that counts how it is used.
private final class CountingEngine: FileSearchEngine, @unchecked Sendable {
    private(set) var saves = 0
    private(set) var warms = 0
    func search(_ query: String, limit: Int) async -> FileSearchOutcome { .hits([]) }
    func status() async -> FileSearchStatus? { nil }
    func keepWarm() { warms += 1 }
    func save() { saves += 1 }
}

private final class Counter: @unchecked Sendable { var value = 0 }

struct FileSearchHostTests {
    @Test func nothingStartsUntilItIsAskedTo() async {
        let made = Counter()
        let host = FileSearchHost { made.value += 1; return CountingEngine() }

        #expect(!host.isRunning)
        #expect(made.value == 0)
        guard case .failed(let message) = await host.search("x", limit: 5) else { Issue.record("expected a failure"); return }
        #expect(message == "File search is turned off")
        #expect(await host.status() == nil)
        host.keepWarm(); host.save()   // harmless without an engine
        #expect(made.value == 0)
    }

    @Test func startingCreatesOneEngineAndUsesIt() async {
        let made = Counter()
        let engine = CountingEngine()
        let host = FileSearchHost { made.value += 1; return engine }

        host.start(); host.start()
        #expect(host.isRunning)
        #expect(made.value == 1)

        guard case .hits = await host.search("x", limit: 5) else { Issue.record("expected hits"); return }
        host.keepWarm(); host.save()
        #expect(engine.warms == 1)
        #expect(engine.saves == 1)
    }
}
