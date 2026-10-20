import SwiftUI

/// Search field and list on one piece of clear glass. Clear glass lets the
/// window behind show through, so a faint scrim keeps the text readable.
struct LauncherCard: View {
    let model: LauncherViewModel

    @Environment(\.colorScheme) private var colorScheme

    private let shape = RoundedRectangle(cornerRadius: LauncherMetrics.cornerRadius, style: .continuous)

    /// Typing runs a search. Changes the model makes itself (reset, entering
    /// a mode) start their own, so they don't go through here.
    private var queryBinding: Binding<String> {
        Binding(
            get: { model.query },
            set: { model.query = $0; model.queryChanged() }
        )
    }

    /// Dark in dark mode so white labels read over clear glass; a light tint in
    /// light mode.
    private var scrim: Color {
        colorScheme == .dark ? .black.opacity(0.28) : .white.opacity(0.15)
    }

    /// Clear glass in dark mode; in light mode regular glass, which frosts and
    /// brightens like Spotlight instead of showing a dark wallpaper through.
    private var glass: Glass {
        colorScheme == .dark ? .clear : .regular
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: queryBinding, mode: model.mode, placeholder: model.defaultPlaceholder, focusToken: model.focusToken)

            if !model.results.isEmpty {
                Divider().opacity(0.5)
                ResultList(model: model)
                if let message = model.errorMessage {
                    Divider().opacity(0.5)
                    ActionErrorBar(message: message)
                }
            }
        }
        .frame(width: LauncherMetrics.width)
        .background(shape.fill(scrim))
        .glassEffect(glass, in: shape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.15), radius: 24, y: 10)
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

/// The rows. It reads the results and the selection itself, so moving the
/// selection redraws the list and not the card around it.
private struct ResultList: View {
    let model: LauncherViewModel

    private var height: CGFloat {
        CGFloat(min(model.results.count, LauncherMetrics.maxRows)) * LauncherMetrics.rowHeight
            + LauncherMetrics.listPadding * 2
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ResultRows(items: model.results, selectedID: model.selectedID) { model.activate($0) }
                .padding(LauncherMetrics.listPadding)
            }
            .scrollIndicators(.never)
            .frame(height: height)
            .onChange(of: model.selectedID) {
                if let id = model.selectedID { proxy.scrollTo(id) }
            }
        }
    }
}
