import Foundation
import Testing
@testable import Launch

/// Lets a test change what the "system" reports between refreshes.
private final class FakeSystem: @unchecked Sendable {
    var fullDiskAccess = false
    var spotlightConflict = true
    var engineHasFullDiskAccess = false

    var probes: OnboardingModel.Probes {
        OnboardingModel.Probes(
            fullDiskAccess: { [self] in fullDiskAccess },
            spotlightConflict: { [self] _ in spotlightConflict }
        )
    }

    var engine: any FileSearching { Engine(system: self) }

    private struct Engine: FileSearching {
        let system: FakeSystem
        func search(_ query: String, limit: Int) async -> FileSearchOutcome { .hits([]) }
        func keepWarm() {}
        func status() async -> FileSearchStatus? {
            let json = #"{"ready":true,"progress":null,"full_disk_access":\#(system.engineHasFullDiskAccess),"entries":1,"index_bytes":1}"#
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try? decoder.decode(FileSearchStatus.self, from: Data(json.utf8))
        }
    }
}

@MainActor
struct OnboardingModelTests {
    /// Each test gets its own settings: the hosted tests share the app's real
    /// UserDefaults, and must not touch the user's tour progress.
    private func isolatedDefaults() -> UserDefaults {
        let name = "OnboardingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func model(_ system: FakeSystem = FakeSystem(), defaults: UserDefaults? = nil) -> OnboardingModel {
        let defaults = defaults ?? isolatedDefaults()
        return OnboardingModel(
            hotKey: HotKeySettings(), features: FeatureSettings(defaults: defaults),
            fileSearch: system.engine, probes: system.probes, defaults: defaults
        )
    }

    @Test func walksThroughTheStepsAndStopsAtTheEnds() {
        let model = model()
        #expect(model.step == .welcome)
        #expect(model.isFirstStep)

        model.back()
        #expect(model.step == .welcome)

        model.next(); #expect(model.step == .permissions)
        model.next(); #expect(model.step == .options)
        model.next(); #expect(model.step == .ready)
        #expect(model.isLastStep)

        model.next()
        #expect(model.step == .ready)

        model.back()
        #expect(model.step == .options)
    }

    @Test func restartGoesBackToTheWelcomeStep() {
        let model = model()
        model.next(); model.next()
        model.restart()
        #expect(model.step == .welcome)
    }

    @Test func refreshNoticesPermissionsChangingInSystemSettings() async {
        let system = FakeSystem()
        let model = model(system)
        #expect(!model.fullDiskAccessGranted)
        #expect(model.spotlightConflict)

        system.fullDiskAccess = true
        system.spotlightConflict = false
        await model.refresh()
        #expect(model.fullDiskAccessGranted)
        #expect(!model.spotlightConflict)
    }

    @Test func grantingAccessAfterTheEngineStartedNeedsARestart() async {
        let system = FakeSystem()           // the engine started without access
        let model = model(system)
        await model.refresh()
        #expect(!model.needsRestartForFullDiskAccess)

        system.fullDiskAccess = true        // granted while the window is open
        await model.refresh()
        #expect(model.needsRestartForFullDiskAccess)
    }

    @Test func noRestartWhenTheEngineAlreadyHadAccess() async {
        let system = FakeSystem()
        system.fullDiskAccess = true
        system.engineHasFullDiskAccess = true
        let model = model(system)
        await model.refresh()
        #expect(!model.needsRestartForFullDiskAccess)
    }

    @Test func finishReportsWhetherToRestart() async {
        let system = FakeSystem()
        let model = model(system)
        var reported: [Bool] = []
        model.onFinish = { reported.append($0) }

        model.finish()
        system.fullDiskAccess = true
        await model.refresh()
        model.finish()

        #expect(reported == [false, true])
    }

    // MARK: Persistence

    @Test func theStepSurvivesARestart() {
        let defaults = isolatedDefaults()
        let first = model(defaults: defaults)
        first.next(); first.next()
        #expect(first.step == .options)

        // A new process: same settings, new model.
        let second = model(defaults: defaults)
        #expect(second.step == .options)
        #expect(!OnboardingModel.isCompleted(in: defaults))
    }

    @Test func movingBackIsSavedToo() {
        let defaults = isolatedDefaults()
        let first = model(defaults: defaults)
        first.next(); first.next(); first.back()
        #expect(model(defaults: defaults).step == .permissions)
    }

    @Test func aFreshInstallStartsAtTheWelcomeStep() {
        let fresh = model()
        #expect(fresh.step == .welcome)
        #expect(!OnboardingModel.isCompleted(in: isolatedDefaults()))
    }

    @Test func finishingMarksTheTourDoneAndForgetsTheStep() {
        let defaults = isolatedDefaults()
        let first = model(defaults: defaults)
        first.next(); first.next(); first.next()
        first.finish()

        #expect(OnboardingModel.isCompleted(in: defaults))
        // Opened again from the menu, it starts over rather than at the end.
        #expect(model(defaults: defaults).step == .welcome)
    }

    @Test func leavingTheWindowMidwayDoesNotFinishTheTour() {
        let defaults = isolatedDefaults()
        let first = model(defaults: defaults)
        first.next()
        // (closing the window changes nothing in the model)
        #expect(!OnboardingModel.isCompleted(in: defaults))
        #expect(model(defaults: defaults).step == .permissions)
    }

    @Test func restartingTheTourFromTheMenuResetsTheSavedStep() {
        let defaults = isolatedDefaults()
        let first = model(defaults: defaults)
        first.next(); first.next()
        first.restart()
        #expect(model(defaults: defaults).step == .welcome)
    }

    @Test func aGarbageSavedStepFallsBackToWelcome() {
        let defaults = isolatedDefaults()
        defaults.set(99, forKey: "onboardingStep")
        #expect(model(defaults: defaults).step == .welcome)
    }

    @Test func requestingARestartCallsTheHook() {
        let model = model()
        var restarts = 0
        model.onRestartRequested = { restarts += 1 }
        model.requestRestart()
        #expect(restarts == 1)
    }
}
