import SwiftUI

/// What sits behind the selected row: a piece of regular glass on the card's
/// clear glass, with the glow breathing round its border in `colors`.
///
/// There is one of these for the whole list. It slides from row to row (see
/// `ResultRows`) instead of one fading out as another fades in, so the glow keeps
/// breathing as the selection moves.
struct RowSelection: View {
    static let cornerRadius: CGFloat = 12
    /// How slowly the glow breathes; see `RowGlow`.
    private static let glowPeriod: TimeInterval = 40

    let colors: [Color]

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    var body: some View {
        Color.clear
            .glassEffect(.regular, in: shape)
            .overlay {
                RowGlow(colors: colors, cornerRadius: Self.cornerRadius, isActive: true, period: Self.glowPeriod)
            }
    }
}
