import AppKit
import Testing
@testable import Launch

private struct RowsProvider: SearchProvider {
    let id = "rows"
    let triggers: [String] = []
    let includedInDefaultSearch = true
    let defaultLimit = 10
    let log: ActionLog

    func results(for query: ParsedQuery) async -> [LauncherItem] {
        (1...3).map { n in
            LauncherItem(
                id: "rows:\(n)",
                title: "Row \(n)",
                icon: .symbol("circle"),
                primary: .init(title: "Open") { [log] in log.events.append("primary \(n)"); return .done },
                command: .init(title: "Reveal") { [log] in log.events.append("command \(n)"); return .done },
                option: .init(title: "Force") { [log] in log.events.append("option \(n)"); return n == 3 ? .failed("nope") : .done }
            )
        }
    }
}

private final class ActionLog { var events: [String] = [] }

@MainActor
struct LauncherViewModelTests {
    private func model(log: ActionLog = ActionLog()) async -> LauncherViewModel {
        let model = LauncherViewModel(router: QueryRouter(providers: [RowsProvider(log: log)]))
        model.query = "row"
        model.queryChanged()
        for _ in 0..<100 where model.results.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        return model
    }

    @Test func firstRowIsSelectedWhenResultsArrive() async {
        let model = await model()
        #expect(model.results.count == 3)
        #expect(model.selectedID == "rows:1")
    }

    @Test func selectionMovesAndStopsAtTheEnds() async {
        let model = await model()
        model.moveSelection(-1)
        #expect(model.selectedID == "rows:1")
        model.moveSelection(1); model.moveSelection(1); model.moveSelection(1)
        #expect(model.selectedID == "rows:3")
        model.moveSelection(-1)
        #expect(model.selectedID == "rows:2")
    }

    @Test func modifiersPickTheMatchingAction() async {
        let log = ActionLog()
        let model = await model(log: log)
        var dismissed = 0
        model.onDismiss = { dismissed += 1 }

        model.activate(modifiers: [])
        model.activate(modifiers: .command)
        model.activate(modifiers: .option)
        #expect(log.events == ["primary 1", "command 1", "option 1"])
        #expect(dismissed == 3)
    }

    @Test func aFailedActionKeepsTheLauncherOpenAndShowsTheError() async {
        let log = ActionLog()
        let model = await model(log: log)
        var dismissed = 0
        model.onDismiss = { dismissed += 1 }

        model.moveSelection(1); model.moveSelection(1)
        model.activate(modifiers: .option)
        #expect(dismissed == 0)
        #expect(model.errorMessage == "nope")

        // Typing clears the message.
        model.query = "row 2"
        model.queryChanged()
        #expect(model.errorMessage == nil)
    }

    @Test func clickingARowActivatesThatRow() async {
        let log = ActionLog()
        let model = await model(log: log)
        model.activate(model.results[1])
        #expect(log.events == ["primary 2"])
    }

    @Test func typingATriggerTurnsIntoABadge() async throws {
        let model = LauncherViewModel(router: QueryRouter(providers: [ModeProvider(rows: ["file"])]))
        model.query = "f cv"
        model.queryChanged()
        #expect(model.mode?.name == "Things")
        #expect(model.query == "cv")
        for _ in 0..<100 where model.results.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.results.map(\.title) == ["file"])
    }

    @Test func oldRowsAndSelectionStayUntilTheNewResultsArrive() async throws {
        let provider = ModeProvider(rows: ["first"])
        let model = LauncherViewModel(router: QueryRouter(providers: [provider]))
        model.query = "a"
        model.queryChanged()
        for _ in 0..<100 where model.results.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.results.map(\.title) == ["first"])
        let selected = model.selectedID

        // The next search is slow and answers with different rows.
        provider.state.rows = ["second", "third"]
        provider.state.delay = .milliseconds(120)
        model.query = "ab"
        model.queryChanged()

        try await Task.sleep(for: .milliseconds(40))
        #expect(model.results.map(\.title) == ["first"])   // not blanked
        #expect(model.selectedID == selected)

        for _ in 0..<100 where model.results.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.results.map(\.title) == ["second", "third"])
        #expect(model.selectedID == model.results.first?.id)
    }

    @Test func noMatchesClearTheOldRows() async throws {
        let provider = ModeProvider(rows: ["first"])
        let model = LauncherViewModel(router: QueryRouter(providers: [provider]))
        model.query = "a"
        model.queryChanged()
        for _ in 0..<100 where model.results.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        provider.state.rows = []
        model.query = "zzz"
        model.queryChanged()
        for _ in 0..<100 where !model.results.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.results.isEmpty)
    }
}

/// Mutable canned results, shared by reference with the test.
private final class ProviderState { var rows: [String]; var delay: Duration = .zero; init(_ rows: [String]) { self.rows = rows } }

private struct ModeProvider: SearchProvider {
    let id = "things"
    let triggers = ["f"]
    let includedInDefaultSearch = true
    let defaultLimit = 10
    let modeInfo: ModeInfo? = ModeInfo(name: "Things", placeholder: "Search things")
    let state: ProviderState

    init(rows: [String]) { state = ProviderState(rows) }

    func results(for query: ParsedQuery) async -> [LauncherItem] {
        if state.delay > .zero { try? await Task.sleep(for: state.delay) }
        return state.rows.map { title in
            LauncherItem(id: "things:\(title)", title: title, icon: .symbol("circle"), primary: .init(title: "Open") { .done })
        }
    }
}
