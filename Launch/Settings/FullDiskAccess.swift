import AppKit
import Darwin

enum FullDiskAccess {
    /// The system TCC database can only be read with Full Disk Access, and
    /// trying without it fails at once, with no prompt. This is the same test
    /// fsearch uses at startup, so the two agree.
    static var isGranted: Bool {
        let fd = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}
