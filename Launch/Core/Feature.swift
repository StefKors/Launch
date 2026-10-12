import Foundation

/// A capability beyond opening apps, which the user can switch on or off.
enum Feature: String, CaseIterable, Identifiable {
    case fileSearch
    case kill

    var id: String { rawValue }

    /// The provider that implements it.
    var providerID: String {
        switch self {
        case .fileSearch: "files"
        case .kill: "processes"
        }
    }

    var title: String {
        switch self {
        case .fileSearch: "File Search"
        case .kill: "Kill"
        }
    }

    var detail: String {
        switch self {
        case .fileSearch: "Find files and folders on your Mac. Choose File Search under a query, or start with “f ”."
        case .kill: "Quit or force-quit running processes. Start with “kill ” and a name."
        }
    }

    /// Shown in settings, the mode badge and the result rows.
    var icon: LauncherItem.Icon {
        switch self {
        case .fileSearch: .file(path: "/System/Library/CoreServices/Finder.app")
        case .kill: .tile(symbol: "cpu.fill", tint: .red)
        }
    }

    static func feature(forProvider id: String) -> Feature? {
        allCases.first { $0.providerID == id }
    }
}
