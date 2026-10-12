import Foundation
import Testing
@testable import Launch

/// Stands in for fsearch: returns a fixed outcome and records the requests.
private final class FakeEngine: FileSearching, @unchecked Sendable {
    var outcome: FileSearchOutcome
    private(set) var requests: [(query: String, limit: Int)] = []
    private(set) var warmed = 0

    init(_ outcome: FileSearchOutcome) { self.outcome = outcome }

    func search(_ query: String, limit: Int) async -> FileSearchOutcome {
        requests.append((query, limit))
        return outcome
    }
    func status() async -> FileSearchStatus? { nil }
    func keepWarm() { warmed += 1 }
}

private func hit(_ path: String, kind: String = "file") -> FileHit {
    FileHit(kind: kind, path: path, size: 0, mtime: 0, score: 0)
}

@MainActor
struct FileProviderTests {
    private let plain = ParsedQuery(raw: "report", text: "report", trigger: nil)
    private let exclusive = ParsedQuery(raw: "f report", text: "report", trigger: "f")

    @Test func hitsBecomeRowsWithFileActions() async throws {
        let engine = FakeEngine(.hits([hit("/Users/me/Documents/report.pdf")]))
        let rows = await FileProvider(engine: engine).results(for: exclusive)

        let row = try #require(rows.first)
        #expect(row.title == "report.pdf")
        #expect(row.primary.title == "Open")
        #expect(row.command?.title == "Reveal in Finder")
        #expect(row.option?.title == "Copy Path")
        #expect(engine.warmed == 1)
    }

    @Test func plainQueryOffersFileSearchWithoutSearching() async throws {
        let engine = FakeEngine(.hits([hit("/a/report.pdf")]))
        let rows = await FileProvider(engine: engine).results(for: plain)

        // One row, no file results yet: those wait for file mode.
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.title == "File Search")
        #expect(row.subtitle == "Search files for “report”")
        #expect(row.primary.title == "Search Files")
        guard case .file(let iconPath) = row.icon else { Issue.record("expected the Finder icon"); return }
        #expect(iconPath == "/System/Library/CoreServices/Finder.app")
        #expect(engine.requests.isEmpty)
    }

    @Test func fileSearchRowEntersFileMode() async throws {
        let engine = FakeEngine(.hits([hit("/a/cv.pdf")]))
        let provider = FileProvider(engine: engine)
        let cv = ParsedQuery(raw: "cv.pdf", text: "cv.pdf", trigger: nil)

        let row = try #require(await provider.results(for: cv).first)
        guard case .enterMode(let providerID, let text) = row.primary.perform() else { Issue.record("expected enterMode"); return }
        #expect(providerID == "files")
        // The badge stands for the trigger, so the field keeps only the text.
        #expect(text == "cv.pdf")
        #expect(QueryRouter(providers: [provider]).mode(forProvider: providerID)?.name == "Files")
    }

    @Test func fileSearchRowKeepsTheLauncherOpenAndShowsFiles() async throws {
        let provider = FileProvider(engine: FakeEngine(.hits([hit("/Users/me/cv.pdf")])))
        let model = LauncherViewModel(router: QueryRouter(providers: [provider]))
        model.query = "cv.pdf"
        model.queryChanged()
        for _ in 0..<100 where model.results.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.results.map(\.title) == ["File Search"])

        var dismissed = false
        model.onDismiss = { dismissed = true }
        model.activate()
        for _ in 0..<100 where model.results.first?.title == "File Search" { try await Task.sleep(for: .milliseconds(10)) }

        #expect(!dismissed)
        #expect(model.mode?.name == "Files")
        #expect(model.query == "cv.pdf")
        #expect(model.results.map(\.title) == ["cv.pdf"])

        // Backspace on the field once the text is gone leaves the mode.
        #expect(!model.canExitMode)
        model.query = ""
        #expect(model.canExitMode)
        model.exitMode()
        #expect(model.mode == nil)
        for _ in 0..<100 where model.results.first?.title != "File Search" && !model.results.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.query == "")
    }

    @Test func fileSearchRowNeedsTwoCharacters() async {
        let engine = FakeEngine(.hits([]))
        let short = ParsedQuery(raw: "r", text: "r", trigger: nil)
        #expect(await FileProvider(engine: engine).results(for: short).isEmpty)
    }

    @Test func fileModeAllowsOneCharacterAndListsEverythingIncludingBundles() async {
        let engine = FakeEngine(.hits([
            hit("/Applications/Safari.app", kind: "dir"),
            hit("/Applications/Safari.app/Contents/Info.plist"),
            hit("/Users/me/safari-notes.txt"),
        ]))
        let short = ParsedQuery(raw: "f s", text: "s", trigger: "f")
        let rows = await FileProvider(engine: engine).results(for: short)
        #expect(rows.count == 3)
        #expect(engine.requests.last?.query == "s")
    }

    @Test func indexingShowsARowInFileMode() async throws {
        let engine = FakeEngine(.indexing(progress: "0.4M entries so far"))
        let provider = FileProvider(engine: engine)

        // A plain query never touches the engine, so it can't be "indexing".
        #expect(await provider.results(for: plain).map(\.title) == ["File Search"])

        let row = try #require(await provider.results(for: exclusive).first)
        #expect(row.title == "Indexing files…")
        #expect(row.subtitle == "0.4M entries so far")
        // The row explains itself and keeps the launcher open.
        guard case .failed = row.primary.perform() else { Issue.record("should stay open"); return }
    }

    @Test func failuresShowARowAndSupersededSearchesStaySilentInFileMode() async {
        let failing = FileProvider(engine: FakeEngine(.failed("boom")))
        #expect(await failing.results(for: exclusive).map(\.title) == ["File search unavailable"])

        let superseded = FileProvider(engine: FakeEngine(.superseded))
        #expect(await superseded.results(for: exclusive).isEmpty)
    }
}
