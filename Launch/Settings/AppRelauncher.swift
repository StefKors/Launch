import AppKit

enum AppRelauncher {
    /// Quits and starts a fresh copy. The new copy waits a second so this one
    /// has let go of the file index first (only one process may write it).
    static func relaunch(showLauncher: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        let extra = showLauncher ? " --args --show" : ""
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"\(extra)", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
