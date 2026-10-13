import SwiftUI

struct OnboardingView: View {
    let model: OnboardingModel

    static let size = CGSize(width: 540, height: 560)

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .padding(.horizontal, 32)
                .padding(.top, 36)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            OnboardingFooter(model: model)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: WelcomeStepView()
        case .permissions: PermissionsStepView(model: model)
        case .options: OptionsStepView(model: model)
        case .ready: ReadyStepView(model: model)
        }
    }
}

/// Back and Continue (or the last step's Start), under the dots.
private struct OnboardingFooter: View {
    let model: OnboardingModel

    var body: some View {
        HStack {
            StepIndicator(count: OnboardingStep.allCases.count, current: model.step.rawValue)
            Spacer()
            if !model.isFirstStep {
                Button("Back") { model.back() }
            }
            if model.isLastStep {
                Button(model.needsRestartForFullDiskAccess ? "Restart and Start" : "Start Launch") { model.finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { model.next() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .frame(height: 64)
    }
}
