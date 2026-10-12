import SwiftUI

struct OptionsStepView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 8) {
            StepHeader(title: "Make it yours", subtitle: "All optional. You can change these any time in Settings.")
            Form {
                ShortcutSection(hotKey: model.hotKey)
                Section("General") {
                    LaunchAtLoginToggle()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}
