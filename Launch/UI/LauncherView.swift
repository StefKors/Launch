import SwiftUI

enum LauncherMetrics {
    /// The card itself.
    static let width: CGFloat = 540
    static let cornerRadius: CGFloat = 22
    static let searchHeight: CGFloat = 52
    static let rowHeight: CGFloat = 36
    static let maxRows = 10
    static let listPadding: CGFloat = 8
    /// Only taken when an action fails and its error shows.
    static let errorHeight: CGFloat = 34
    static let dividerHeight: CGFloat = 1

    /// Transparent room around the card inside the window. The card's shadow is
    /// drawn into it; without it the shadow is cut off at the window's edge.
    static let shadowMargin: CGFloat = 48

    /// How long the card takes to blur in, and to blur away before its window is
    /// closed.
    static let transitionDuration: TimeInterval = 0.16

    static let cardMaxHeight = searchHeight
        + dividerHeight + CGFloat(maxRows) * rowHeight + listPadding * 2
        + dividerHeight + errorHeight

    /// The panel is always full height and transparent below the card, so
    /// resizing the list never resizes a window. On a short screen it is cut
    /// down and the list shows fewer rows (see `PanelController`).
    static let panelSize = CGSize(
        width: width + shadowMargin * 2,
        height: cardMaxHeight + shadowMargin * 2
    )
}

struct LauncherView: View {
    @Bindable var model: LauncherViewModel

    private let shape = RoundedRectangle(cornerRadius: LauncherMetrics.cornerRadius, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            card
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LauncherMetrics.shadowMargin)
        .padding(.top, LauncherMetrics.shadowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.onDismiss() }
    }

    /// Search field and list on one piece of clear glass. Clear glass lets the
    /// window behind show through, so a faint scrim keeps the text readable.
    private var card: some View {
        VStack(spacing: 0) {
            SearchField(text: queryBinding, mode: model.mode, placeholder: model.defaultPlaceholder, focusToken: model.focusToken)

            if !model.results.isEmpty {
                Divider().opacity(0.5)
                resultList
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

    /// Typing runs a search. Changes the model makes itself (reset, entering
    /// a mode) start their own, so they don't go through here.
    private var queryBinding: Binding<String> {
        Binding(
            get: { model.query },
            set: { model.query = $0; model.queryChanged() }
        )
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.results) { item in
                        ResultRow(item: item, isSelected: item.id == model.selectedID)
                            .id(item.id)
                            .onTapGesture { model.activate(item) }
                    }
                }
                .padding(LauncherMetrics.listPadding)
            }
            .scrollIndicators(.never)
            .frame(height: listHeight)
            .onChange(of: model.selectedID) {
                if let id = model.selectedID { proxy.scrollTo(id) }
            }
        }
    }

    private var listHeight: CGFloat {
        CGFloat(min(model.results.count, LauncherMetrics.maxRows)) * LauncherMetrics.rowHeight
            + LauncherMetrics.listPadding * 2
    }
}
