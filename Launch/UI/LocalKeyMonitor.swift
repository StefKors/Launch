import AppKit

/// A key-down monitor for this app's own windows. Return true from `handler` to
/// swallow the event.
///
/// AppKit calls the monitor on the main thread but doesn't say so in its
/// signature, so the hop onto the main actor is made here, once, instead of at
/// every place that listens for keys.
final class LocalKeyMonitor {
    private let handler: @MainActor (NSEvent) -> Bool
    private var token: Any?

    init(handler: @escaping @MainActor (NSEvent) -> Bool) {
        self.handler = handler
    }

    isolated deinit { remove() }

    func install() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [handler] event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { handler(event) }
            return consumed ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
