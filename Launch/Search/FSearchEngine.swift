import Foundation
import LaunchFSearch
import Synchronization

/// fsearch running inside this process, through the C interface in `Rust/`.
///
/// Every call into Rust goes through one serial queue, which also owns the
/// engine handle. A search that is no longer the newest by the time its turn
/// comes is skipped, so fast typing never builds up a backlog.
nonisolated final class FSearchEngine: FileSearching, @unchecked Sendable {
    private let queue = DispatchQueue(label: "launch.fsearch", qos: .userInteractive)
    private let latestSearch = Mutex(0)
    private let startError = Mutex<String?>(nil)
    /// Only touched on `queue`.
    private var handle: OpaquePointer?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Begins indexing in the background. `directory` holds the index.
    init(directory: URL, home: String = NSHomeDirectory()) {
        queue.async { [self] in
            var error: UnsafeMutablePointer<CChar>?
            handle = lf_start(home, directory.path, &error)
            if handle == nil {
                startError.withLock { $0 = error.map { String(cString: $0) } ?? "fsearch failed to start" }
            }
            lf_free_string(error)
        }
    }

    func search(_ query: String, limit: Int) async -> FileSearchOutcome {
        let ticket = latestSearch.withLock { $0 += 1; return $0 }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard ticket == latestSearch.withLock({ $0 }) else {
                    return continuation.resume(returning: .superseded)
                }
                continuation.resume(returning: run(query, limit: limit))
            }
        }
    }

    func status() async -> FileSearchStatus? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let handle, let json = lf_status(handle) else {
                    return continuation.resume(returning: nil)
                }
                defer { lf_free_string(json) }
                continuation.resume(returning: try? decoder.decode(FileSearchStatus.self, from: Data(bytes: json, count: strlen(json))))
            }
        }
    }

    func keepWarm() {
        queue.async { [self] in
            if let handle { lf_keep_warm(handle, 400) }
        }
    }

    /// Writes the index to disk; call before quitting.
    func save() {
        queue.sync {
            if let handle { lf_save(handle) }
        }
    }

    // MARK: Rust calls (on `queue`)

    private struct SearchReply: Decodable {
        let ok: Bool
        let error: String?
        let indexing: Bool
        let hits: [FileHit]
    }

    private func run(_ query: String, limit: Int) -> FileSearchOutcome {
        guard let handle else {
            return .failed(startError.withLock { $0 } ?? "fsearch is starting")
        }
        guard let json = lf_search(handle, query, UInt32(clamping: limit)) else {
            return .failed("fsearch returned nothing")
        }
        defer { lf_free_string(json) }
        guard let reply = try? decoder.decode(SearchReply.self, from: Data(bytes: json, count: strlen(json))) else {
            return .failed("unreadable reply from fsearch")
        }
        if reply.ok { return .hits(reply.hits) }
        return reply.indexing ? .indexing(progress: reply.error) : .failed(reply.error ?? "search failed")
    }
}
