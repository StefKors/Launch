import AppKit
import EventKit
import Observation

/// The menu-bar item: the magnifier, the featured event's text beside it, and
/// the menu. It is AppKit rather than `MenuBarExtra`, because SwiftUI menus
/// drop the icons and colour dots on rows.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let calendar: CalendarStore
    private let updater: Updater
    private let showLauncher: () -> Void
    private let showWelcome: () -> Void
    private let showSettings: () -> Void

    init(
        calendar: CalendarStore,
        updater: Updater,
        showLauncher: @escaping () -> Void,
        showWelcome: @escaping () -> Void,
        showSettings: @escaping () -> Void
    ) {
        self.calendar = calendar
        self.updater = updater
        self.showLauncher = showLauncher
        self.showWelcome = showWelcome
        self.showSettings = showSettings
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Launch")
        statusItem.button?.imagePosition = .imageLeading
        observeCalendar()
    }

    /// Keeps the text beside the icon current. Observation fires once per
    /// change, so it is set up again after each one. The controller is
    /// main-actor isolated and lives as long as the app, so it can be held.
    private func observeCalendar() {
        withObservationTracking {
            statusItem.button?.title = calendar.menuBarText.map { " \($0)" } ?? ""
        } onChange: {
            Task { @MainActor in self.observeCalendar() }
        }
    }

    // MARK: - Menu

    /// Built each time the menu opens, so it shows the current events.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addCalendarItems(to: menu)

        #if DEBUG
        menu.addItem(item("Show Launcher", action: #selector(showLauncherAction)))
        menu.addItem(item("Welcome Guide…", action: #selector(showWelcomeAction)))
        #endif
        let updates = item("Check for Updates…", action: #selector(checkForUpdatesAction))
        updates.isEnabled = updater.canCheckForUpdates
        menu.addItem(updates)
        menu.addItem(item("Settings…", action: #selector(showSettingsAction), key: ","))
        menu.addItem(.separator())
        let quit = item("Quit Launch", action: #selector(NSApplication.terminate(_:)), key: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func addCalendarItems(to menu: NSMenu) {
        guard calendar.isAuthorized else {
            if calendar.access == .notDetermined {
                menu.addItem(item("Allow Calendar Access…", action: #selector(requestCalendarAccess)))
            } else {
                menu.addItem(item("Calendar Access Is Off", action: #selector(openCalendarPrivacy)))
            }
            menu.addItem(.separator())
            return
        }

        if let featured = calendar.featured {
            let open = item("Open in Calendar", action: #selector(openFeatured), symbol: "calendar")
            open.representedObject = featured
            menu.addItem(open)
            menu.addItem(item("Dismiss Event", action: #selector(dismissFeatured), symbol: "xmark.circle"))
            menu.addItem(.separator())
        }
        addDay("Today", calendar.today, emptyText: "No events today", to: menu)
        addDay("Tomorrow", calendar.tomorrow, emptyText: "No events tomorrow", to: menu)
        menu.addItem(.separator())
    }

    private func addDay(_ title: String, _ events: [CalendarEvent], emptyText: String, to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: title))
        if events.isEmpty {
            let none = NSMenuItem(title: emptyText, action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for event in events {
            let row = NSMenuItem(title: event.title, action: #selector(openEvent(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = event
            row.attributedTitle = rowTitle(for: event)
            menu.addItem(row)
        }
    }

    /// “9:30 AM – 10:00 AM  ●  Standup”: the times in secondary colour, then a
    /// dot in the calendar's colour, then the title.
    private func rowTitle(for event: CalendarEvent) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let secondary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let row = NSMutableAttributedString(string: CalendarAgenda.timeText(for: event) + "  ", attributes: secondary)
        row.append(NSAttributedString(
            string: "●  ",
            attributes: [.font: font, .foregroundColor: nsColor(event.calendarColor)]
        ))
        row.append(NSAttributedString(
            string: event.title,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        ))
        return row
    }

    private func nsColor(_ color: EventColor?) -> NSColor {
        guard let color else { return .secondaryLabelColor }
        return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    private func item(_ title: String, action: Selector, key: String = "", symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        return item
    }

    // MARK: - Actions

    @objc private func openEvent(_ sender: NSMenuItem) {
        guard let event = sender.representedObject as? CalendarEvent, let url = CalendarAgenda.openTarget(for: event) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openFeatured(_ sender: NSMenuItem) {
        guard let event = sender.representedObject as? CalendarEvent, let url = CalendarAgenda.calendarURL(for: event) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func dismissFeatured() {
        calendar.dismissFeatured()
    }

    @objc private func requestCalendarAccess() {
        Task { await calendar.requestAccess() }
    }

    @objc private func openCalendarPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    @objc private func showLauncherAction() { showLauncher() }
    @objc private func showWelcomeAction() { showWelcome() }
    @objc private func checkForUpdatesAction() { updater.checkForUpdates() }
    @objc private func showSettingsAction() { showSettings() }
}
