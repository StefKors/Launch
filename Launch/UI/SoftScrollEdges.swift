import SwiftUI

/// How much of each end of a scrolling list is faded, in points. A fade grows from
/// nothing as you scroll away from an end and shrinks again as you come back to
/// it, so at rest nothing is faded and a fade never pops in.
struct ScrollFades: Equatable {
    var top: CGFloat
    var bottom: CGFloat

    static let none = ScrollFades(top: 0, bottom: 0)
}

/// Opaque in the middle, easing out to nothing over `fades` at each end.
private struct FadeMask: View {
    let fades: ScrollFades
    let length: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(1 - fades.top / length), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fades.top)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(1 - fades.bottom / length)], startPoint: .top, endPoint: .bottom)
                .frame(height: fades.bottom)
        }
    }
}

extension View {
    /// Fades the view out at an end that has more to scroll to, so a row is never
    /// cut off by a hard line. `length` is the longest a fade gets; give the
    /// scroll view content margins as long, so that what it scrolls to stays
    /// clear of it.
    func softEdges(_ fades: ScrollFades, length: CGFloat) -> some View {
        mask { FadeMask(fades: fades, length: length) }
    }
}
