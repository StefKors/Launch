import Foundation
import Observation

/// State of the first-run flow: which step is showing, and what the system
/// says about the permissions it asks for.
///
/// The step is saved as the user moves, and the tour counts as unfinished
/// until `finish()`. So it comes back, at the same step, after a restart in
/// the middle (granting Full Disk Access makes macOS offer one).
@Observable
final class OnboardingModel {
    /// What to ask the system. Replaced in tests.
    struct Probes {
        var fullDiskAccess: () -> Bool = { FullDiskAccess.isGranted }
        var spotlightConflict: (GlobalHotKey.Shortcut) -> Bool = { SpotlightShortcut.conflicts(with: $0) }
    }

    private(set) var step: OnboardingStep = .welcome
    private(set) var fullDiskAccessGranted = false
    /// Spotlight still holds the shortcut we want.
    private(set) var spotlightConflict = false
    /// The file engine started without Full Disk Access, so it is skipping
    /// protected folders until the app restarts.
    private(set) var engineSkipsProtectedFolders = false

    let hotKey: HotKeySettings

    @ObservationIgnored private let fileSearch: (any FileSearching)?
    @ObservationIgnored private let probes: Probes
    @ObservationIgnored private let defaults: UserDefaults
    /// Restart the app (the permissions step offers it once access is granted).
    @ObservationIgnored var onRestartRequested: () -> Void = {}
    /// Called with whether the app should restart to pick up Full Disk Access.
    @ObservationIgnored var onFinish: (_ restart: Bool) -> Void = { _ in }

    private static let stepKey = "onboardingStep"
    private static let completedKey = "onboardingCompleted"

    /// Whether the user has been through the tour to the end.
    static func isCompleted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completedKey)
    }

    init(hotKey: HotKeySettings, fileSearch: (any FileSearching)?, probes: Probes = Probes(), defaults: UserDefaults = .standard) {
        self.hotKey = hotKey
        self.fileSearch = fileSearch
        self.probes = probes
        self.defaults = defaults
        // Pick up where the user left off, unless they already finished.
        if !Self.isCompleted(in: defaults), let saved = OnboardingStep(rawValue: defaults.integer(forKey: Self.stepKey)) {
            step = saved
        }
        fullDiskAccessGranted = probes.fullDiskAccess()
        spotlightConflict = probes.spotlightConflict(hotKey.shortcut)
    }

    var isFirstStep: Bool { step.previous == nil }
    var isLastStep: Bool { step.next == nil }

    /// Full Disk Access arrived after the engine started, so the engine
    /// can't see the newly allowed folders until Launch restarts.
    var needsRestartForFullDiskAccess: Bool {
        fullDiskAccessGranted && engineSkipsProtectedFolders
    }

    func next() {
        if let next = step.next { go(to: next) }
    }

    func back() {
        if let previous = step.previous { go(to: previous) }
    }

    /// Back to the first step (reopening the tour from the menu).
    func restart() {
        go(to: .welcome)
    }

    func requestRestart() {
        onRestartRequested()
    }

    func finish() {
        defaults.set(true, forKey: Self.completedKey)
        defaults.removeObject(forKey: Self.stepKey)
        onFinish(needsRestartForFullDiskAccess)
    }

    private func go(to new: OnboardingStep) {
        step = new
        defaults.set(new.rawValue, forKey: Self.stepKey)
    }

    /// Re-reads the system state. The user changes these in System Settings
    /// while this window is open, so it runs on a timer.
    func refresh() async {
        fullDiskAccessGranted = probes.fullDiskAccess()
        spotlightConflict = probes.spotlightConflict(hotKey.shortcut)
        if let status = await fileSearch?.status() {
            engineSkipsProtectedFolders = !status.fullDiskAccess
        }
    }
}
