import SwiftUI

/// A short explanatory line with an icon, for settings and onboarding.
struct NoteLabel: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
