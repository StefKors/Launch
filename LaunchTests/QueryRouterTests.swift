import Testing
@testable import Launch

/// A provider that records what it was asked and returns canned rows.
private struct StubProvider: SearchProvider {
    let id: String
    var triggers: [String] = []
    var includedInDefaultSearch = true
    var defaultLimit = 10
    var rows: [String] = []
    var delay: Duration = .zero
    var modeInfo: ModeInfo?

    func results(for query: ParsedQuery) async -> [LauncherItem] {
        if delay > .zero { try? await Task.sleep(for: delay) }
        return rows.map { title in
            LauncherItem(
                id: "\(id):\(title)",
                title: title,
                icon: .symbol("circle"),
                primary: .init(title: "Open") { .done }
            )
        }
    }
}

@MainActor
struct QueryRouterTests {
    private func router(_ providers: [StubProvider]) -> QueryRouter {
        QueryRouter(providers: providers)
    }

    @Test func plainQueryGoesToDefaultProviders() {
        let router = router([
            StubProvider(id: "apps"),
            StubProvider(id: "kill", triggers: ["kill"], includedInDefaultSearch: false),
        ])
        let (query, active) = router.parse("safari")
        #expect(query.text == "safari")
        #expect(query.trigger == nil)
        #expect(active.map(\.id) == ["apps"])
    }

    @Test func wordTriggerNeedsASpace() {
        let router = router([StubProvider(id: "apps"), StubProvider(id: "kill", triggers: ["kill"], includedInDefaultSearch: false)])

        let routed = router.parse("kill chrome")
        #expect(routed.providers.map(\.id) == ["kill"])
        #expect(routed.query.text == "chrome")
        #expect(routed.query.isExclusive)

        // "killer" or a bare "kill" is just a search for an app.
        #expect(router.parse("killer").providers.map(\.id) == ["apps"])
        #expect(router.parse("kill").providers.map(\.id) == ["apps"])
    }

    @Test func emptyTextAfterTriggerStillRoutes() {
        let router = router([StubProvider(id: "kill", triggers: ["kill"], includedInDefaultSearch: false)])
        let routed = router.parse("kill ")
        #expect(routed.query.text == "")
        #expect(routed.query.isExclusive)
    }

    @Test func symbolTriggerNeedsNoSpace() {
        let router = router([StubProvider(id: "apps"), StubProvider(id: "files", triggers: ["/"])])
        let routed = router.parse("/notes")
        #expect(routed.providers.map(\.id) == ["files"])
        #expect(routed.query.text == "notes")
    }

    @Test func triggerIsCaseInsensitiveButTextKeepsItsCase() {
        let router = router([StubProvider(id: "files", triggers: ["f"])])
        let routed = router.parse("  F Report.PDF ext:pdf")
        #expect(routed.query.trigger == "f")
        #expect(routed.query.text == "Report.PDF ext:pdf")
    }

    @Test func longestTriggerWins() {
        let router = router([
            StubProvider(id: "short", triggers: ["f"]),
            StubProvider(id: "long", triggers: ["file"]),
        ])
        #expect(router.parse("file x").providers.map(\.id) == ["long"])
        #expect(router.parse("f x").providers.map(\.id) == ["short"])
    }

    @Test func listChangesOnceWhenEveryProviderAnswersInTime() async {
        let router = router([
            StubProvider(id: "slow", rows: ["slow1", "slow2"], delay: .milliseconds(60)),
            StubProvider(id: "fast", rows: ["fast1"]),
        ])
        var updates: [[String]] = []
        await router.search("x") { updates.append($0.map(\.title)) }

        // One update with everything, in provider order. Publishing the fast
        // provider alone first made rows vanish and reappear.
        #expect(updates == [["slow1", "slow2", "fast1"]])
    }

    @Test func aSlowProviderDoesNotHoldBackTheRest() async {
        let router = router([
            StubProvider(id: "slow", rows: ["slow1"], delay: .milliseconds(400)),
            StubProvider(id: "fast", rows: ["fast1"]),
        ])
        var updates: [[String]] = []
        await router.search("x", partialAfter: .milliseconds(50)) { updates.append($0.map(\.title)) }

        #expect(updates == [["fast1"], ["slow1", "fast1"]])
    }

    @Test func nothingIsPublishedBeforeAnyProviderAnswers() async {
        let router = router([StubProvider(id: "slow", rows: ["slow1"], delay: .milliseconds(200))])
        var updates: [[String]] = []
        await router.search("x", partialAfter: .milliseconds(30)) { updates.append($0.map(\.title)) }

        // The deadline passes with nothing in: the old rows stay put.
        #expect(updates == [["slow1"]])
    }

    @Test func noMatchesPublishesAnEmptyList() async {
        let router = router([StubProvider(id: "p", rows: [])])
        var updates: [[String]] = []
        await router.search("x") { updates.append($0.map(\.title)) }
        #expect(updates == [[]])
    }

    @Test func typedTriggerBecomesAMode() {
        let router = router([
            StubProvider(id: "apps"),
            StubProvider(id: "files", triggers: ["f", "file", "/"], modeInfo: ModeInfo(name: "Files", placeholder: "Search files")),
        ])
        let detected = router.detectMode(in: "f cv.pdf")
        #expect(detected?.mode.providerID == "files")
        #expect(detected?.mode.name == "Files")
        #expect(detected?.text == "cv.pdf")

        #expect(router.detectMode(in: "/cv")?.text == "cv")
        #expect(router.detectMode(in: "cv.pdf") == nil)
        // A trigger with no badge keeps routing without a mode.
        #expect(self.router([StubProvider(id: "x", triggers: ["x"])]).detectMode(in: "x y") == nil)
    }

    @Test func searchInAModeRunsOnlyThatProviderWithTheFieldText() async {
        let router = router([
            StubProvider(id: "apps", rows: ["app"]),
            StubProvider(id: "files", triggers: ["f"], rows: ["file"], modeInfo: ModeInfo(name: "Files", placeholder: "")),
        ])
        let mode = router.mode(forProvider: "files")
        var rows: [String] = []
        await router.search("anything", mode: mode) { rows = $0.map(\.title) }
        #expect(rows == ["file"])
    }

    @Test func defaultSearchCapsEachProvider_exclusiveDoesNot() async {
        let rows = (1...9).map { "r\($0)" }
        let capped = StubProvider(id: "p", triggers: ["p"], defaultLimit: 3, rows: rows)
        let router = router([capped])

        var plain: [LauncherItem] = []
        await router.search("x") { plain = $0 }
        #expect(plain.count == 3)

        var exclusive: [LauncherItem] = []
        await router.search("p x") { exclusive = $0 }
        #expect(exclusive.count == 9)
    }
}
