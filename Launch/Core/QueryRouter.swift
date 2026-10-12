import Foundation

/// Decides which providers see a query and merges what they return.
struct QueryRouter {
    let providers: [any SearchProvider]

    /// Longest triggers first, so "kill " wins over a hypothetical "k ".
    func parse(_ raw: String) -> (query: ParsedQuery, providers: [any SearchProvider]) {
        let trimmed = raw.drop(while: \.isWhitespace)
        let lowered = trimmed.lowercased()
        let triggers = providers
            .flatMap { provider in provider.triggers.map { (trigger: $0, provider: provider) } }
            .sorted { $0.trigger.count > $1.trigger.count }

        for (trigger, provider) in triggers {
            let needsSpace = trigger.last?.isLetter ?? false
            let prefix = needsSpace ? trigger + " " : trigger
            guard lowered.hasPrefix(prefix) else { continue }
            // Keep the user's casing: only the trigger is case-insensitive.
            let text = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            let query = ParsedQuery(raw: raw, text: text, trigger: trigger)
            return (query, [provider])
        }

        let text = raw.trimmingCharacters(in: .whitespaces)
        let query = ParsedQuery(raw: raw, text: text, trigger: nil)
        return (query, providers.filter(\.includedInDefaultSearch))
    }

    /// The mode for a provider, as the badge shows it.
    func mode(forProvider id: String) -> SearchMode? {
        guard let provider = providers.first(where: { $0.id == id }),
              let info = provider.modeInfo,
              let trigger = provider.triggers.first else { return nil }
        return SearchMode(providerID: id, trigger: trigger, name: info.name, placeholder: info.placeholder, icon: info.icon)
    }

    /// A typed trigger ("kill ", "f ", "/") turns into a mode: the mode, and
    /// the text that followed the trigger.
    func detectMode(in raw: String) -> (mode: SearchMode, text: String)? {
        let (query, active) = parse(raw)
        guard let trigger = query.trigger, let provider = active.first, let info = provider.modeInfo else { return nil }
        let mode = SearchMode(providerID: provider.id, trigger: trigger, name: info.name, placeholder: info.placeholder, icon: info.icon)
        return (mode, query.text)
    }

    /// Calls `onUpdate` with the merged list. It waits until every provider
    /// has answered, so the list changes once, from old rows to complete new
    /// ones (publishing as each provider finished made rows vanish and come
    /// back). If a provider is still busy after `partialAfter`, what has
    /// arrived is shown and the rest follows. Rows keep provider order no
    /// matter which finishes first. In a mode only that provider runs, and
    /// `text` is all the field holds.
    func search(
        _ text: String,
        mode: SearchMode? = nil,
        partialAfter: Duration = .milliseconds(150),
        onUpdate: @MainActor ([LauncherItem]) -> Void
    ) async {
        let query: ParsedQuery
        let active: [any SearchProvider]
        if let mode, let provider = providers.first(where: { $0.id == mode.providerID }) {
            query = ParsedQuery(raw: text, text: text.trimmingCharacters(in: .whitespaces), trigger: mode.trigger)
            active = [provider]
        } else {
            (query, active) = parse(text)
        }
        guard !active.isEmpty else { return onUpdate([]) }
        var buckets = Array(repeating: [LauncherItem](), count: active.count)
        var answered = 0
        var deadlinePassed = false
        let deadline = -1

        await withTaskGroup(of: (Int, [LauncherItem]).self) { group in
            for (index, provider) in active.enumerated() {
                group.addTask { @MainActor in
                    let items = await provider.results(for: query)
                    let limit = query.isExclusive ? Int.max : provider.defaultLimit
                    return (index, Array(items.prefix(limit)))
                }
            }
            group.addTask { @MainActor in
                try? await Task.sleep(for: partialAfter)
                return (deadline, [])
            }

            for await (index, items) in group {
                if Task.isCancelled { return }
                if index == deadline {
                    deadlinePassed = true
                    // Nothing has answered yet: keep showing the old rows.
                    if answered == 0 { continue }
                } else {
                    buckets[index] = items
                    answered += 1
                }
                if answered == active.count {
                    onUpdate(buckets.flatMap { $0 })
                    group.cancelAll()
                    return
                }
                if deadlinePassed { onUpdate(buckets.flatMap { $0 }) }
            }
        }
    }
}
