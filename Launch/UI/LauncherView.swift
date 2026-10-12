import SwiftUI

enum LauncherMetrics {
    /// The card itself.
    static let width: CGFloat = 680
    static let searchHeight: CGFloat = 60
    static let rowHeight: CGFloat = 48
    static let footerHeight: CGFloat = 40
    static let maxRows = 8
    static let listPadding: CGFloat = 8

    /// Transparent room around the card inside the window. The card's shadow is
    /// drawn into it; without it the shadow is cut off at the window's edge.
    static let shadowMargin: CGFloat = 40

    static let cardMaxHeight = searchHeight + CGFloat(maxRows) * rowHeight + listPadding * 2 + footerHeight + 1

    /// The panel is always full height and transparent below the card, so
    /// resizing the list never resizes a window.
    static let panelSize = CGSize(
        width: width + shadowMargin * 2,
        height: cardMaxHeight + shadowMargin * 2
    )
}

struct LauncherView: View {
    @Bindable var model: LauncherViewModel

    var body: some View {
        VStack(spacing: 0) {
            card
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LauncherMetrics.shadowMargin)
        .padding(.top, LauncherMetrics.shadowMargin)
        .frame(width: LauncherMetrics.panelSize.width, height: LauncherMetrics.panelSize.height, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.onDismiss() }
    }

    private var card: some View {
        VStack(spacing: 0) {
            SearchField(text: queryBinding, mode: model.mode, placeholder: model.defaultPlaceholder, focusToken: model.focusToken)

            if !model.results.isEmpty {
                Divider()
                resultList
                Divider()
                ActionHintBar(item: model.selectedItem, errorMessage: model.errorMessage, canGoBack: model.canExitMode)
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Swallow taps so only the transparent area dismisses.
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
