import Darwin
import Foundation

nonisolated struct RunningProcess: Identifiable, Sendable {
    let pid: pid_t
    let name: String
    /// Path of the executable, when the system lets us read it.
    let path: String?

    var id: pid_t { pid }
}

nonisolated enum ProcessList {
    /// Processes owned by the current user, excluding this app.
    static func snapshot() -> [RunningProcess] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride)))
        guard count > 0 else { return [] }

        let me = getuid()
        let myPID = getpid()
        var result: [RunningProcess] = []
        for pid in pids.prefix(count) where pid > 1 && pid != myPID {
            var info = proc_bsdshortinfo()
            let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size, info.pbsi_uid == me else { continue }

            var nameBuffer = [CChar](repeating: 0, count: 256)
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let path = executablePath(of: pid)
            let name = nameLength > 0
                ? String(cString: nameBuffer)
                : path.map { ($0 as NSString).lastPathComponent } ?? "pid \(pid)"
            result.append(RunningProcess(pid: pid, name: name, path: path))
        }
        return result
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
