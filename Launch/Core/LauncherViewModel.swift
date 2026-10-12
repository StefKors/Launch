import AppKit
import Observation

@Observable
final class LauncherViewModel {
    var query = ""
    private(set) var results: [LauncherItem] = []
    var selectedID: LauncherItem.ID?
    /// Bumped on every show so the view can put focus back in the field.
    private(set) var focusToken = 0
    private(set) var errorMessage: String?
    /// Set when one provider is searched on its own ("Files"). The field then
    /// holds only the search text; the badge stands for the trigger.
    private(set) var mode: SearchMode?

    @ObservationIgnored var onDismiss: () -> Void = {}
    @ObservationIgnored private let router: QueryRouter
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// The next results belong to a new query, so the first row gets selected.
    @ObservationIgnored private var selectFirstOnNextResults = true

    init(router: QueryRouter) {
        self.router = router
    }

    var selectedItem: LauncherItem? {
        results.first { $0.id == selectedID }
    }

    /// Empty the field; with nothing typed there are no results.
    func reset() {
        mode = nil
        query = ""
        // Rows from the last time the panel was open don't belong here.
        results = []
        errorMessage = nil
        focusToken += 1
        queryChanged()
    }

    func cancel() {
        searchTask?.cancel()
    }

    /// Call after the field's text changes. Typing a trigger ("f ", "kill ")
    /// turns it into the mode badge.
    func queryChanged() {
        if mode == nil, let detected = router.detectMode(in: query) {
            mode = detected.mode
            query = detected.text
        }
        search()
    }

    /// Backspace on an empty field: back to searching everything.
    func exitMode() {
        guard mode != nil else { return }
        mode = nil
        query = ""
        search()
    }

    /// True when backspace would leave the mode.
    var canExitMode: Bool { mode != nil && query.isEmpty }

    private func search() {
        searchTask?.cancel()
        errorMessage = nil
        // The old rows and their selection stay on screen until the new
        // results arrive, so the list never flashes empty in between.
        selectFirstOnNextResults = true
        let text = query
        let mode = mode
        searchTask = Task {
            await router.search(text, mode: mode) { [weak self] items in
                self?.apply(items)
            }
        }
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? (delta > 0 ? -1 : results.count)
        let next = min(max(current + delta, 0), results.count - 1)
        selectedID = results[next].id
    }

    func activate(_ item: LauncherItem? = nil, modifiers: NSEvent.ModifierFlags = []) {
        guard let item = item ?? selectedItem else { return }
        let action: LauncherItem.Action
        if modifiers.contains(.command), let command = item.command {
            action = command
        } else if modifiers.contains(.option), let option = item.option {
            action = option
        } else {
            action = item.primary
        }
        switch action.perform() {
        case .done:
            onDismiss()
        case .enterMode(let providerID, let text):
            guard let mode = router.mode(forProvider: providerID) else { return }
            self.mode = mode
            query = text
            search()
        case .failed(let message):
            errorMessage = message
        }
    }

    private func apply(_ items: [LauncherItem]) {
        results = items
        if selectFirstOnNextResults || !items.contains(where: { $0.id == selectedID }) {
            selectedID = items.first?.id
        }
        selectFirstOnNextResults = false
    }
}
