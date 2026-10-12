import AppKit
import Observation
import Sparkle

/// Software updates, through Sparkle. The feed and the public key that
/// signatures are checked against are in `Config/Info.plist`.
///
/// Sparkle checks about once a day, shows its own window when there is a new
/// version, and downloads, verifies, replaces the app and relaunches it.
@Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// `startingUpdater: false` for the unit-test host, which must not go
    /// to the network.
    init(startingUpdater: Bool) {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: startingUpdater, updaterDelegate: nil, userDriverDelegate: self)
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }

    /// "1.0.0 (1)", from the app's Info.plist.
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Launch has no Dock icon or main window, so a scheduled update window
    /// can open unseen behind other apps. Saying we support gentle reminders
    /// lets Sparkle show it, and we bring the app forward when it does.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate()
    }
}
