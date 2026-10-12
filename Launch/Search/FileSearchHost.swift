import Foundation
import Synchronization

/// A file search engine that can be saved. `FSearchEngine` is the real one.
nonisolated protocol FileSearchEngine: FileSearching {
    func save()
}

extension FSearchEngine: FileSearchEngine {}

/// Stands in for the file search engine from launch, and starts the real one
/// only when File Search is on. A disabled feature then costs nothing: no
/// index in memory and no disk watching.
///
/// There is no way to stop an engine once started (its threads end with the
/// process), so switching the feature off hides it at once and the engine
/// goes away at the next launch.
nonisolated final class FileSearchHost: FileSearching, @unchecked Sendable {
    private let makeEngine: @Sendable () -> any FileSearchEngine
    private let engine = Mutex<(any FileSearchEngine)?>(nil)

    init(makeEngine: @escaping @Sendable () -> any FileSearchEngine) {
        self.makeEngine = makeEngine
    }

    var isRunning: Bool { current != nil }

    /// Starts the engine if it isn't running yet.
    func start() {
        engine.withLock { if $0 == nil { $0 = makeEngine() } }
    }

    func search(_ query: String, limit: Int) async -> FileSearchOutcome {
        guard let current else { return .failed("File search is turned off") }
        return await current.search(query, limit: limit)
    }

    func status() async -> FileSearchStatus? {
        await current?.status()
    }

    func keepWarm() {
        current?.keepWarm()
    }

    func save() {
        current?.save()
    }

    private var current: (any FileSearchEngine)? {
        engine.withLock { $0 }
    }
}
