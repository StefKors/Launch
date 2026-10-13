import SwiftUI

/// The scrolling list of results, with the selection highlight behind its rows
/// and a soft fade where there is more to scroll to.
///
/// The highlight is not part of the scrolling content. It sits in the list's
/// viewport and moves in the same animation as the scroll position. When the
/// selection moves to a row that is already in view, only the highlight moves.
/// When it moves past the edge, the highlight's place on screen stays the same
/// and the rows glide past it, so there is nothing for the two to disagree about
/// however closely the scroll keeps time. (Inside the content, a highlight that
/// started a frame ahead of the scroll dipped off the edge and bounced back.)
struct ResultList: View {
    let items: [LauncherItem]
    let selectedID: LauncherItem.ID?
    let onActivate: (LauncherItem) -> Void

    @State private var position = ScrollPosition()
    @State private var viewport = ListViewport()
    /// Where the highlight is on screen, from the top of the list.
    @State private var highlightY: CGFloat
    /// An animated move is under way, so the highlight is not following the
    /// scroll offset directly.
    @State private var isFollowing = false
    @State private var followTask: Task<Void, Never>?

    init(items: [LauncherItem], selectedID: LauncherItem.ID?, onActivate: @escaping (LauncherItem) -> Void) {
        self.items = items
        self.selectedID = selectedID
        self.onActivate = onActivate
        // The list starts scrolled to the top, with its margin above the first row.
        let index = items.firstIndex { $0.id == selectedID } ?? 0
        _highlightY = State(initialValue: CGFloat(index) * LauncherMetrics.rowHeight + LauncherMetrics.listInset)
    }

    private var selectedIndex: Int? {
        items.firstIndex { $0.id == selectedID }
    }

    private var height: CGFloat {
        CGFloat(min(items.count, LauncherMetrics.maxRows)) * LauncherMetrics.rowHeight + LauncherMetrics.listInset * 2
    }

    var body: some View {
        ScrollView {
            ResultRows(items: items, selectedID: selectedID, onActivate: onActivate)
                .padding(.horizontal, LauncherMetrics.listPadding)
        }
        .scrollPosition($position)
        .contentMargins(.vertical, LauncherMetrics.listInset, for: .scrollContent)
        .scrollIndicators(.never)
        .onScrollGeometryChange(for: ListViewport.self) { ListViewport($0) } action: { _, new in
            viewport = new
            settleHighlight()
        }
        .background(alignment: .top) {
            if let index = selectedIndex {
                ListHighlight(colors: IconPalette.colors(for: items[index].icon), y: highlightY)
            }
        }
        .softEdges(viewport.fades(length: LauncherMetrics.listInset), length: LauncherMetrics.listInset)
        .frame(height: height)
        .onChange(of: selectedID) { follow() }
        .onChange(of: items.map(\.id)) { settleHighlight() }
    }

    /// Puts the highlight on the selected row wherever the list is scrolled to
    /// (the user scrolling it, or the results changing), unless a move is under
    /// way.
    private func settleHighlight() {
        guard !isFollowing, let index = selectedIndex else { return }
        highlightY = CGFloat(index) * LauncherMetrics.rowHeight - viewport.offsetY
    }

    /// Moves the highlight to the selected row and scrolls just far enough to
    /// show it, in one animation.
    private func follow() {
        guard let index = selectedIndex else { return }
        let target = viewport.offset(toReveal: index)
        followTask?.cancel()
        isFollowing = true
        withAnimation(LauncherMetrics.selectionAnimation) {
            highlightY = CGFloat(index) * LauncherMetrics.rowHeight - target
            if target != viewport.offsetY { position.scrollTo(y: target) }
        }
        followTask = Task {
            // Long enough for the animation to finish.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isFollowing = false
            settleHighlight()
        }
    }
}

/// The selection highlight, at `y` from the top of the list.
private struct ListHighlight: View {
    let colors: [Color]
    let y: CGFloat

    var body: some View {
        RowSelection(colors: colors)
            .frame(height: LauncherMetrics.rowHeight)
            .padding(.horizontal, LauncherMetrics.listPadding)
            .offset(y: y)
    }
}

/// Where the list is scrolled to, and how far it can go.
private struct ListViewport: Equatable {
    var offsetY: CGFloat = 0
    var insetTop: CGFloat = 0
    var insetBottom: CGFloat = 0
    var height: CGFloat = 0
    var contentHeight: CGFloat = 0

    init() {}

    init(_ geometry: ScrollGeometry) {
        offsetY = geometry.contentOffset.y
        insetTop = geometry.contentInsets.top
        insetBottom = geometry.contentInsets.bottom
        height = geometry.containerSize.height
        contentHeight = geometry.contentSize.height
    }

    /// How much of each end to fade: as far as the list has scrolled from it, up
    /// to `length`.
    func fades(length: CGFloat) -> ScrollFades {
        let fromTop = offsetY + insetTop
        let fromBottom = contentHeight + insetBottom - (offsetY + height)
        return ScrollFades(top: min(max(fromTop, 0), length), bottom: min(max(fromBottom, 0), length))
    }

    /// The offset that shows row `index` in full and clear of the fade at each
    /// end, moving as little as it can.
    func offset(toReveal index: Int) -> CGFloat {
        let top = CGFloat(index) * LauncherMetrics.rowHeight
        let bottom = top + LauncherMetrics.rowHeight
        var target = offsetY
        if top < offsetY + insetTop {
            target = top - insetTop
        } else if bottom > offsetY + height - insetBottom {
            target = bottom + insetBottom - height
        }
        return min(max(target, -insetTop), max(contentHeight + insetBottom - height, -insetTop))
    }
}
