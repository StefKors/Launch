import Foundation
import Testing
@testable import Launch

@MainActor
struct ProcessProviderTests {
    private func spawnSleeper() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["3600"]
        try process.run()
        return process
    }

    private func find(_ pid: pid_t, query: String) async -> LauncherItem? {
        let parsed = ParsedQuery(raw: "kill \(query)", text: query, trigger: "kill")
        return await ProcessProvider().results(for: parsed).first { $0.id == "processes:\(pid)" }
    }

    @Test func quitSendsSIGTERM() async throws {
        let sleeper = try spawnSleeper()
        defer { if sleeper.isRunning { sleeper.terminate() } }

        let item = try #require(await find(sleeper.processIdentifier, query: "sleep"))
        #expect(item.title == "sleep")
        #expect(item.primary.title == "Quit")

        guard case .done = item.primary.perform() else { Issue.record("quit failed"); return }
        sleeper.waitUntilExit()
        #expect(sleeper.terminationReason == .uncaughtSignal)
        #expect(sleeper.terminationStatus == SIGTERM)
    }

    @Test func forceQuitSendsSIGKILL() async throws {
        let sleeper = try spawnSleeper()
        defer { if sleeper.isRunning { sleeper.terminate() } }

        let item = try #require(await find(sleeper.processIdentifier, query: "sleep"))
        let force = try #require(item.option)
        #expect(force.title == "Force Quit")

        guard case .done = force.perform() else { Issue.record("force quit failed"); return }
        sleeper.waitUntilExit()
        #expect(sleeper.terminationStatus == SIGKILL)
    }

    @Test func processesOfOtherUsersAreNotListed() {
        let pids = ProcessList.snapshot().map(\.pid)
        #expect(!pids.contains(1))          // launchd runs as root
        #expect(!pids.contains(getpid()))   // never offers to kill itself
    }

    @Test func signalingAProcessWeDoNotOwnReportsAnError() throws {
        // launchd (pid 1) belongs to root: EPERM, not a crash or a kill.
        let result = ProcessProvider.send(SIGTERM, to: 1)
        guard case .failed(let message) = result else { Issue.record("expected failure"); return }
        #expect(message.contains("Not permitted"))
    }

    @Test func emptyQueryListsOnlyWindowedApps() async {
        let parsed = ParsedQuery(raw: "kill ", text: "", trigger: "kill")
        let rows = await ProcessProvider().results(for: parsed)
        // No helper daemons without a search term.
        #expect(rows.allSatisfy { $0.icon.isFile })
    }
}

private extension LauncherItem.Icon {
    var isFile: Bool {
        if case .file = self { true } else { false }
    }
}
