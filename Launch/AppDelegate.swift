import AppKit

/// Owns the long-lived pieces: providers, the panel and the global hotkey.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panelController: PanelController
    let hotKeySettings = HotKeySettings()
    let fileEngine: FSearchEngine?
    private(set) lazy var settingsWindow = SettingsWindowController(hotKey: hotKeySettings, fileSearch: fileEngine)
    private(set) lazy var onboardingWindow = OnboardingWindowController(hotKey: hotKeySettings, fileSearch: fileEngine) { [weak self] in
        self?.panelController.show()
    }
    /// The unit-test host runs this delegate too; it must not start indexing
    /// the disk or take the global shortcut.
    private let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private var hotKey: GlobalHotKey?

    override init() {
        // Kept apart from the user's own fsearch index (~/Library/Application
        // Support/FSearch), so the two never share a writer.
        let indexDirectory = URL.applicationSupportDirectory.appending(path: "Launch/FSearch", directoryHint: .isDirectory)
        let engine = isTestHost ? nil : FSearchEngine(directory: indexDirectory)
        fileEngine = engine

        var providers: [any SearchProvider] = [AppProvider(index: AppIndex())]
        if let engine { providers.append(FileProvider(engine: engine)) }
        providers.append(ProcessProvider())
        let model = LauncherViewModel(router: QueryRouter(providers: providers))
        panelController = PanelController(model: model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        fileEngine?.save()
    }
}
