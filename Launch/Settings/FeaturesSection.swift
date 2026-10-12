import SwiftUI

/// Every feature beyond opening apps, each with a switch.
struct FeaturesSection: View {
    let features: FeatureSettings
    /// Extra line under a feature (for example, that it is still running).
    var footnotes: [Feature: String] = [:]

    var body: some View {
        Section {
            ForEach(Feature.allCases) { feature in
                FeatureToggleRow(
                    icon: feature.icon,
                    title: feature.title,
                    detail: feature.detail,
                    isOn: Binding(
                        get: { features.isEnabled(feature) },
                        set: { features.setEnabled(feature, $0) }
                    )
                )
                if let note = footnotes[feature] {
                    NoteLabel(text: note, systemImage: "info.circle")
                }
            }
        } header: {
            Text("Features")
        } footer: {
            Text("Opening apps is always on.")
        }
    }
}
