import SwiftUI

/// Search field and list on one piece of clear glass. Clear glass lets the
/// window behind show through, so a faint scrim keeps the text readable.
struct LauncherCard: View {
    let model: LauncherViewModel

    private let shape = RoundedRectangle(cornerRadius: LauncherMetrics.cornerRadius, style: .continuous)

    /// Typing runs a search. Changes the model makes itself (reset, entering
    /// a mode) start their own, so they don't go through here.
    private var queryBinding: Binding<String> {
        Binding(
            get: { model.query },
            set: { model.query = $0; model.queryChanged() }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: queryBinding, mode: model.mode, placeholder: model.defaultPlaceholder, focusToken: model.focusToken)

            if !model.results.isEmpty {
                Divider().opacity(0.5)
                ModelResultList(model: model)
                if let message = model.errorMessage {
                    Divider().opacity(0.5)
                    ActionErrorBar(message: message)
                }
            }
        }
        .frame(width: LauncherMetrics.width)
        .background(shape.fill(.black.opacity(0.28)))
        .glassEffect(.clear, in: shape)
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        // Blurs in as it appears and out as it goes.
        .blur(radius: model.isPresented ? 0 : 14)
        .opacity(model.isPresented ? 1 : 0)
        .scaleEffect(model.isPresented ? 1 : 0.97, anchor: .top)
        .animation(model.isPresented ? .smooth(duration: LauncherMetrics.transitionDuration) : .easeIn(duration: LauncherMetrics.transitionDuration), value: model.isPresented)
        // Swallow taps so only the transparent area around the card dismisses.
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}

/// The list, reading the results and the selection itself, so moving the
/// selection redraws the list and not the card around it.
private struct ModelResultList: View {
    let model: LauncherViewModel

    var body: some View {
        ResultList(items: model.results, selectedID: model.selectedID) { model.activate($0) }
    }
}
