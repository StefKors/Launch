import Foundation

/// Background colour of an icon tile. The UI maps it to a real colour.
enum IconTint: Equatable {
    case red
}

/// One row in the launcher. Providers build these; the UI only renders them
/// and runs the action matching the pressed modifier.
struct LauncherItem: Identifiable {
    enum Icon: Equatable {
        /// Icon the system shows for the file or app at this path.
        case file(path: String)
        case symbol(String)
        /// A symbol on a coloured rounded square, drawn like an app icon.
        case tile(symbol: String, tint: IconTint)
    }

    enum ActionResult {
        case done
        /// Keep the launcher open and search one provider on its own, with
        /// `query` in the field.
        case enterMode(providerID: String, query: String)
        /// Keep the launcher open and show the message in the footer.
        case failed(String)
    }

    struct Action {
        var title: String
        var perform: @MainActor () -> ActionResult
    }

    /// Unique across providers, so prefix it with the provider id.
    let id: String
    var title: String
    var subtitle: String?
    var icon: Icon
    /// Return.
    var primary: Action
    /// Command-Return.
    var command: Action?
    /// Option-Return.
    var option: Action?
}
