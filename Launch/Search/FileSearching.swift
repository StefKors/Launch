import Foundation

nonisolated struct FileHit: Decodable, Identifiable, Sendable {
    /// "file", "dir", "link" or "other".
    let kind: String
    let path: String
    let size: UInt64
    /// Seconds since the Unix epoch.
    let mtime: UInt32
    let score: Int

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var isDirectory: Bool { kind == "dir" }
}

nonisolated enum FileSearchOutcome: Sendable {
    case hits([FileHit])
    /// The first index is still being built; `progress` says how far.
    case indexing(progress: String?)
    case failed(String)
    /// A newer search replaced this one before it ran.
    case superseded
}

nonisolated struct FileSearchStatus: Decodable, Sendable, Equatable {
    let ready: Bool
    let progress: String?
    /// False when consent-gated folders are being skipped.
    let fullDiskAccess: Bool
    let entries: Int
    let indexBytes: Int
}

/// What the file provider needs from a search engine. The in-process fsearch
/// engine is one implementation; a bundled `fsearch serve` daemon behind a
/// socket would be another.
nonisolated protocol FileSearching: Sendable {
    /// `query` uses fsearch's query language, e.g. "main ext:swift".
    func search(_ query: String, limit: Int) async -> FileSearchOutcome
    func status() async -> FileSearchStatus?
    /// Call when the user is about to type, so searches start fast.
    func keepWarm()
}
