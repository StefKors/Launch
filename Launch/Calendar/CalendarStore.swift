import CoreGraphics
import EventKit
import Foundation
import Observation

/// Reads today's and tomorrow's events from Calendar. Refreshes when Calendar
/// changes and every minute, so the next-event text moves on as time passes.
@Observable
final class CalendarStore {
    private static let dismissedKey = "calendar.dismissedEvents"

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var started = false

    private(set) var access = EKEventStore.authorizationStatus(for: .event)
    private(set) var now = Date.now
    private(set) var today: [CalendarEvent] = []
    private(set) var tomorrow: [CalendarEvent] = []
    /// Events the user dismissed from the menu bar, with when each one ends.
    private(set) var dismissed: [String: Date]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.dismissedKey) as? [String: Double] ?? [:]
        dismissed = saved.mapValues(Date.init(timeIntervalSinceReferenceDate:))
    }

    var isAuthorized: Bool { access == .fullAccess }

    /// The event the menu bar features, leaving out dismissed ones.
    var featured: CalendarEvent? {
        CalendarAgenda.featuredEvent(in: today.filter { dismissed[$0.id] == nil }, now: now)
    }

    /// Menu-bar text for the featured event, nil when there is none.
    var menuBarText: String? {
        featured.map { CalendarAgenda.menuBarTitle(for: $0, now: now) }
    }

    /// Hides the featured event from the menu bar until it ends.
    func dismissFeatured() {
        guard let featured else { return }
        dismissed[featured.id] = featured.end
        defaults.set(dismissed.mapValues(\.timeIntervalSinceReferenceDate), forKey: Self.dismissedKey)
    }

    /// Asks for access the first time, then keeps the lists up to date for
    /// the life of the app.
    func start() {
        guard !started else { return }
        started = true
        if access == .notDetermined {
            Task { await requestAccess() }
        }
        refresh()
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                self?.refresh()
            }
        }
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                self.refresh()
            }
        }
    }

    func requestAccess() async {
        _ = try? await eventStore.requestFullAccessToEvents()
        refresh()
    }

    func refresh() {
        access = EKEventStore.authorizationStatus(for: .event)
        now = .now
        dismissed = CalendarAgenda.pruned(dismissed, now: now)
        guard isAuthorized else {
            today = []
            tomorrow = []
            return
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        guard
            let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart),
            let dayAfterStart = calendar.date(byAdding: .day, value: 2, to: todayStart)
        else { return }

        let predicate = eventStore.predicateForEvents(withStart: todayStart, end: dayAfterStart, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { !isDeclined($0) }
            .map(CalendarEvent.init)

        today = CalendarAgenda.events(overlapping: DateInterval(start: todayStart, end: tomorrowStart), in: events)
        tomorrow = CalendarAgenda.events(overlapping: DateInterval(start: tomorrowStart, end: dayAfterStart), in: events)
    }

    /// Declined invitations stay in Calendar, but they aren't part of the day.
    private func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }
}

extension CalendarEvent {
    nonisolated init(_ event: EKEvent) {
        let title = event.title ?? ""
        self.init(
            id: "\(event.eventIdentifier ?? "")-\(event.startDate.timeIntervalSinceReferenceDate)",
            title: title.isEmpty ? "Untitled event" : title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarItemIdentifier: event.calendarItemIdentifier,
            calendarColor: EventColor(event.calendar?.cgColor),
            meetingURL: CalendarAgenda.meetingURL(url: event.url, texts: [event.location ?? "", event.notes ?? ""])
        )
    }
}

extension EventColor {
    nonisolated init?(_ color: CGColor?) {
        guard
            let color,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let rgb = color.converted(to: space, intent: .defaultIntent, options: nil),
            let components = rgb.components, components.count >= 3
        else { return nil }
        self.init(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}
