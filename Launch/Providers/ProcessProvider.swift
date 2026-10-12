import AppKit

/// "kill <name>": quit or force-quit a running process.
struct ProcessProvider: SearchProvider {
    let id = "processes"
    let triggers = ["kill"]
    let modeInfo: ModeInfo? = ModeInfo(name: "Kill", placeholder: "Search running processes")
    let includedInDefaultSearch = false
    let defaultLimit = 0

    func results(for query: ParsedQuery) async -> [LauncherItem] {
        let processes = await Task.detached(priority: .userInitiated) { ProcessList.snapshot() }.value

        return processes
            .compactMap { process -> (RunningProcess, NSRunningApplication?, Double)? in
                // Windowed apps come first and get a boost over background helpers.
                let app = NSRunningApplication(processIdentifier: process.pid)
                let isGUI = app?.activationPolicy == .regular
                let title = app?.localizedName ?? process.name
                if query.text.isEmpty {
                    return isGUI ? (process, app, 0) : nil
                }
                guard let score = FuzzyMatcher.score(query.text, in: title) ?? FuzzyMatcher.score(query.text, in: process.name) else {
                    return nil
                }
                return (process, app, score + (isGUI ? 50 : 0))
            }
            .sorted { ($0.2, $1.0.name) > ($1.2, $0.0.name) }
            .map { item(for: $0.0, app: $0.1) }
    }

    private func item(for process: RunningProcess, app: NSRunningApplication?) -> LauncherItem {
        let pid = process.pid
        let title = app?.localizedName ?? process.name
        let location = process.path.map { ($0 as NSString).abbreviatingWithTildeInPath }
        let icon: LauncherItem.Icon =
            if let path = app?.bundleURL?.path { .file(path: path) } else { .symbol("terminal") }

        return LauncherItem(
            id: "\(id):\(pid)",
            title: title,
            subtitle: ["PID \(pid)", location].compactMap { $0 }.joined(separator: " · "),
            icon: icon,
            primary: .init(title: "Quit") {
                if let app {
                    return app.terminate() ? .done : Self.send(SIGTERM, to: pid)
                }
                return Self.send(SIGTERM, to: pid)
            },
            command: process.path.map { path in
                .init(title: "Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    return .done
                }
            },
            option: .init(title: "Force Quit") {
                Self.send(SIGKILL, to: pid)
            }
        )
    }

    static func send(_ signal: Int32, to pid: pid_t) -> LauncherItem.ActionResult {
        if kill(pid, signal) == 0 { return .done }
        switch errno {
        case ESRCH: return .done // already gone
        case EPERM: return .failed("Not permitted to signal this process")
        default: return .failed(String(cString: strerror(errno)))
        }
    }
}
