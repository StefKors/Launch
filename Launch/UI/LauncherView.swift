import SwiftUI

enum LauncherMetrics {
    static let contentWidth: CGFloat = 480

    static let searchHeight: CGFloat = 64
    static let rowHeight: CGFloat = 36
    static let maxRows = 14
    /// Only taken when an action fails and its error shows.
    static let footerHeight: CGFloat = 44
    /// Room above the first and below the last row, so the list's edge fade
    /// never dims a row you are looking at.
    static let listInset: CGFloat = 16

    /// Transparent room around the content for the blur to fade out in. There
    /// is no card edge: the blur thins out over this distance.
    static let blurMarginX: CGFloat = 250
    static let blurMarginTop: CGFloat = 130
    static let blurMarginBottom: CGFloat = blurMarginTop

    /// What moving the selection animates: the icon and the text both use it,
    /// so a row moves as one.
    static let selectionAnimation = Animation.smooth(duration: 0.15)

    /// How long the launcher takes to blur in, and to blur away before its
    /// window is closed.
    static let transitionDuration: TimeInterval = 0.16

    /// The blur around just the search field.
    static let collapsedBlurHeight = blurMarginTop + searchHeight + blurMarginBottom

    static let contentMaxHeight = searchHeight + CGFloat(maxRows) * rowHeight + listInset * 2 + footerHeight

    /// The window the panel asks for. On a short screen it is cut down and the
    /// list simply shows fewer rows (see `PanelController`).
    static let panelSize = CGSize(
        width: contentWidth + blurMarginX * 2,
        height: contentMaxHeight + blurMarginTop + blurMarginBottom
    )
}

struct LauncherView: View {
    @Bindable var model: LauncherViewModel

    var body: some View {
        VStack(spacing: 0) {
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LauncherMetrics.blurMarginX)
        .padding(.top, LauncherMetrics.blurMarginTop)
        .padding(.bottom, LauncherMetrics.blurMarginBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) { blot }
        .contentShape(Rectangle())
        .onTapGesture { model.onDismiss() }
    }

    /// The blur is one view that is never recreated or resized; it eases its
    /// own height to follow the list (see `ProgressiveBlur`).
    private var blot: some View {
        BlurBlot(height: blurHeight, isPresented: model.isPresented)
            .equatable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The blur is as tall as the content, plus the margin it fades out in.
    private var blurHeight: CGFloat {
        var content = LauncherMetrics.searchHeight
        if !model.results.isEmpty {
            let rows = min(model.results.count, LauncherMetrics.maxRows)
            content += CGFloat(rows) * LauncherMetrics.rowHeight + LauncherMetrics.listInset * 2
        }
        if model.errorMessage != nil { content += LauncherMetrics.footerHeight }
        return LauncherMetrics.blurMarginTop + content + LauncherMetrics.blurMarginBottom
    }

    /// Search field and list. No box around them: the blur behind
    /// is bigger than they are and fades out on every side.
    private var content: some View {
        VStack(spacing: 0) {
            SearchField(text: queryBinding, mode: model.mode, placeholder: model.defaultPlaceholder, focusToken: model.focusToken)

            if !model.results.isEmpty {
                resultList
                if let message = model.errorMessage {
                    ActionErrorBar(message: message)
                }
            }
        }
        .frame(width: LauncherMetrics.contentWidth)
        // Blurs in as it appears and out as it goes.
        .blur(radius: model.isPresented ? 0 : 14)
        .opacity(model.isPresented ? 1 : 0)
        .scaleEffect(model.isPresented ? 1 : 0.97, anchor: .top)
        .animation(model.isPresented ? .smooth(duration: LauncherMetrics.transitionDuration) : .easeIn(duration: LauncherMetrics.transitionDuration), value: model.isPresented)
        // Swallow taps so only the area around the content dismisses.
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
                .padding(.vertical, LauncherMetrics.listInset)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: listHeight)
            .mask { edgeFade }
            .onChange(of: model.selectedID) {
                guard let id = model.selectedID else { return }
                // The selection stays in the middle and the list moves under
                // it, like turning a dial.
                withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    /// Rows thin out towards the top and bottom of the list.
    private var edgeFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: LauncherMetrics.listInset)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: LauncherMetrics.listInset * 3)
        }
    }

    private var listHeight: CGFloat {
        CGFloat(model.results.count) * LauncherMetrics.rowHeight + LauncherMetrics.listInset * 2
    }
}
