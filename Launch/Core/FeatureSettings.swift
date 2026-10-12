import Foundation
import Observation

/// Which features are switched on. Everything starts on.
@Observable
final class FeatureSettings {
    private var states: [Feature: Bool] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after a feature is switched on or off.
    @ObservationIgnored var onChange: (Feature, Bool) -> Void = { _, _ in }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for feature in Feature.allCases {
            states[feature] = defaults.object(forKey: Self.key(feature)) as? Bool ?? true
        }
    }

    func isEnabled(_ feature: Feature) -> Bool {
        states[feature] ?? true
    }

    /// Providers that aren't a switchable feature (apps) are always on.
    func isEnabled(providerID: String) -> Bool {
        Feature.feature(forProvider: providerID).map(isEnabled) ?? true
    }

    func setEnabled(_ feature: Feature, _ enabled: Bool) {
        guard isEnabled(feature) != enabled else { return }
        states[feature] = enabled
        defaults.set(enabled, forKey: Self.key(feature))
        onChange(feature, enabled)
    }

    private static func key(_ feature: Feature) -> String {
        "featureEnabled.\(feature.rawValue)"
    }
}
