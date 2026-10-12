import SwiftUI

struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
