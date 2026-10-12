import AppKit

/// Owns the long-lived pieces: providers, the panel and the global hotkey.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panelController: PanelController
    let hotKeySettings = HotKeySettings()
    let features = FeatureSettings()
    let fileSearch: FileSearchHost
    let updater: Updater
    private(set) lazy var settingsWindow = SettingsWindowController(hotKey: hotKeySettings, features: features, updater: updater, fileSearch: fileSearch)
    private(set) lazy var onboardingWindow = OnboardingWindowController(hotKey: hotKeySettings, features: features, fileSearch: fileSearch) { [weak self] in
        self?.panelController.show()
    }
    /// The unit-test host runs this delegate too; it must not start indexing
    /// the disk or take the global shortcut.
    private let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    /// `--smoke-test`: start, prove the app launches (every library loaded, the
    /// app delegate built), and quit with status 0. scripts/release.sh runs it on
    /// the exported app before notarizing. Like the test host it touches nothing:
    /// no indexing, no shortcut, no update check, no windows.
    private let isSmokeTest = CommandLine.arguments.contains("--smoke-test")
    private var isHeadless: Bool { isTestHost || isSmokeTest }
    private var hotKey: GlobalHotKey?

    override init() {
        // Kept apart from the user's own fsearch index (~/Library/Application
        // Support/FSearch), so the two never share a writer.
        let indexDirectory = URL.applicationSupportDirectory.appending(path: "Launch/FSearch", directoryHint: .isDirectory)
        let host = FileSearchHost { FSearchEngine(directory: indexDirectory) }
        fileSearch = host
        updater = Updater(startingUpdater: !(isTestHost || isSmokeTest))

        // A switched-off feature leaves the router at once, and its engine
        // isn't started at all (see FileSearchHost).
        let features = self.features
        let providers: [any SearchProvider] = [AppProvider(index: AppIndex()), FileProvider(engine: host), ProcessProvider()]
        let router = QueryRouter { providers.filter { features.isEnabled(providerID: $0.id) } }
        panelController = PanelController(model: LauncherViewModel(router: router))
        super.init()

        features.onChange = { feature, enabled in
            if feature == .fileSearch && enabled { host.start() }
        }
        if !(isTestHost || isSmokeTest) && features.isEnabled(.fileSearch) { host.start() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isSmokeTest {
            print("smoke test ok")
            NSApp.terminate(nil)
            return
        }
        guard !isTestHost else { return }
        hotKeySettings.onChange = { [weak self] in self?.registerHotKey() }
        registerHotKey()
        showOnboardingUnlessFinished()
        // Lets a script open the panel without the hotkey.
        if CommandLine.arguments.contains("--show") {
            panelController.show()
        }
    }

    /// (Re)registers the global shortcut. It is released while the recorder
    /// listens, so pressing the old shortcut can't open the launcher then.
    private func registerHotKey() {
        hotKey = nil
        guard !hotKeySettings.isRecording else { return }
        hotKey = GlobalHotKey(hotKeySettings.shortcut) { [panelController] in
            panelController.toggle()
        }
        hotKeySettings.registrationFailed = hotKey == nil
    }

    /// A menu-bar app with no window looks broken on first launch, so walk
    /// the user through the permissions and options. The tour comes back on
    /// every launch, at the step they were on, until they finish it: granting
    /// Full Disk Access means restarting, and the tour must survive that.
    private func showOnboardingUnlessFinished() {
        guard !OnboardingModel.isCompleted() else { return }
        onboardingWindow.show(resume: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        fileSearch.save()
    }
}
