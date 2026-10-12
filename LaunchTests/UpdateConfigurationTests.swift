import Foundation
import Testing
@testable import Launch

/// A wrong feed URL or public key silently breaks updates for everyone who
/// already installed the app, so the shipped configuration is checked here.
struct UpdateConfigurationTests {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    @Test func feedIsTheLatestReleaseAppcastOfThisRepository() throws {
        let feed = try #require(info["SUFeedURL"] as? String)
        #expect(feed == "https://github.com/StefKors/Launch/releases/latest/download/appcast.xml")
        #expect(URL(string: feed)?.scheme == "https", "updates must come over HTTPS")
    }

    @Test func publicKeyIsAnEdDSAKey() throws {
        let key = try #require(info["SUPublicEDKey"] as? String)
        // An Ed25519 public key is 32 bytes, in base64.
        #expect(Data(base64Encoded: key)?.count == 32)
    }

    @Test func automaticChecksAreOnByDefault() {
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
    }

    @Test func theVersionComesFromTheProject() {
        // Both must be present for Sparkle to compare versions.
        #expect(info["CFBundleShortVersionString"] is String)
        #expect(info["CFBundleVersion"] is String)
        #expect(Updater.versionDescription.contains("("))
    }

    @MainActor
    @Test func anUpdaterThatWasNotStartedStaysOffline() {
        let updater = Updater(startingUpdater: false)
        #expect(!updater.canCheckForUpdates)
    }
}
