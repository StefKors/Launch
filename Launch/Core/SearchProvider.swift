import Foundation

struct ParsedQuery: Equatable {
    var raw: String
    /// What to search for: trimmed, with any routing trigger removed.
    var text: String
    /// Set when the query was routed to a single provider ("kill chrome").
    var trigger: String?

    var isExclusive: Bool { trigger != nil }
}

/// How a provider shows up as a mode: the badge in the search field.
struct ModeInfo {
    /// Badge text ("Files").
    var name: String
    /// Placeholder while the field is empty ("Search files").
    var placeholder: String
    /// Small icon in front of the badge text.
    var icon: LauncherItem.Icon? = nil
}

/// The mode the launcher is in: one provider, searched on its own. The
/// trigger text is not part of the field; the badge stands for it.
struct SearchMode: Equatable {
    var providerID: String
    /// The trigger that routes to the provider ("f").
    var trigger: String
    var name: String
    var placeholder: String
    var icon: LauncherItem.Icon?
}

/// A source of launcher results. To add a feature, write a provider and add
/// it to `AppServices`; the router picks up its triggers.
protocol SearchProvider {
    var id: String { get }
    /// Prefixes that send the query to this provider alone. A trigger ending
    /// in a letter needs a space after it ("kill "); a symbol ("/") does not.
    var triggers: [String] { get }
    /// Whether results appear for a query without a trigger.
    var includedInDefaultSearch: Bool { get }
    /// Most rows this provider contributes to a default search.
    var defaultLimit: Int { get }

    /// Set for providers with triggers; nil keeps the old behaviour of routing
    /// without a badge.
    var modeInfo: ModeInfo? { get }

    func results(for query: ParsedQuery) async -> [LauncherItem]
}

extension SearchProvider {
    var modeInfo: ModeInfo? { nil }
}
