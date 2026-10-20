import Foundation

/// An event on the calendar, reduced to what the menu bar and menu show.
nonisolated struct CalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// Calendar's ID for the event, which Calendar.app uses to find it.
    var calendarItemIdentifier: String = ""
    /// The colour of the event's calendar, for the dot in the menu.
    var calendarColor: EventColor? = nil
    /// A video call link from the event, when it has one.
    var meetingURL: URL? = nil
}

/// An sRGB colour, kept as plain numbers so events stay Sendable and testable.
nonisolated struct EventColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

/// Which events the menu bar and menu show, and how they read. Kept apart
/// from EventKit so it can be tested with plain values.
nonisolated enum CalendarAgenda {
    /// Longest title shown in the menu bar, before it is cut with “…”.
    static let maxMenuBarTitleLength = 24

    /// Events that overlap `day`, all-day events first, then by start time.
    static func events(overlapping day: DateInterval, in events: [CalendarEvent]) -> [CalendarEvent] {
        events
            .filter { $0.start < day.end && $0.end > day.start }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.start < rhs.start
            }
    }

    /// The event the menu bar features: the timed event in progress (the one
    /// that started last, if several are), else the next timed event that
    /// hasn't started. All-day events are never featured.
    static func featuredEvent(in events: [CalendarEvent], now: Date) -> CalendarEvent? {
        let timed = events.filter { !$0.isAllDay }
        let inProgress = timed.filter { $0.start <= now && now < $0.end }
        if let current = inProgress.max(by: { $0.start < $1.start }) {
            return current
        }
        return timed.filter { $0.start > now }.min { $0.start < $1.start }
    }

    /// Dismissals whose event hasn't ended yet. The rest are no longer needed.
    static func pruned(_ dismissed: [String: Date], now: Date) -> [String: Date] {
        dismissed.filter { $0.value > now }
    }

    /// “Standup • 22m left” for an event in progress, “Standup • in 15m” for
    /// one that hasn't started, with a long title cut short.
    static func menuBarTitle(for event: CalendarEvent, now: Date) -> String {
        guard let timing = timingText(for: event, now: now) else { return shortened(event.title) }
        return "\(shortened(event.title)) • \(timing)"
    }

    /// “9:30 AM – 10:00 AM”, or “All day”.
    static func timeText(for event: CalendarEvent) -> String {
        guard !event.isAllDay else { return "All day" }
        return "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }

    /// Opens the event itself in Calendar.app, with its details shown. Calendar
    /// has no public link for an event, so this uses the `ical://ekevent` link
    /// it handles: the calendar item ID, and the start time in UTC, which picks
    /// one occurrence of a repeating event.
    static func calendarURL(for event: CalendarEvent) -> URL? {
        guard !event.calendarItemIdentifier.isEmpty else { return nil }
        let id = event.calendarItemIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "ical://ekevent/\(utcStamp(event.start))/\(id)?method=show&options=more")
    }

    /// Where a click on the event goes: its meeting link, else its time in Calendar.app.
    static func openTarget(for event: CalendarEvent) -> URL? {
        event.meetingURL ?? calendarURL(for: event)
    }

    /// The video call link for an event. A link to a known meeting service
    /// wins, found in the event's location, notes or URL. Failing that, the
    /// event's own web URL is used.
    static func meetingURL(url: URL?, texts: [String]) -> URL? {
        let candidates = (texts.flatMap(links(in:)) + [url].compactMap { $0 }).filter(isWebLink)
        if let meeting = candidates.first(where: isMeetingService) {
            return meeting
        }
        return url.flatMap { isWebLink($0) ? $0 : nil }
    }

    private static let meetingHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "gotomeeting.com", "whereby.com", "facetime.apple.com", "chime.aws",
    ]

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
    }

    private static func isWebLink(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    private static func isMeetingService(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func utcStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    /// “in 15m” before a timed event starts, “22m left” while it runs, and
    /// nil once it has ended.
    static func timingText(for event: CalendarEvent, now: Date) -> String? {
        if event.start > now {
            return "in \(duration(event.start.timeIntervalSince(now)))"
        }
        if now < event.end {
            return "\(duration(event.end.timeIntervalSince(now))) left"
        }
        return nil
    }

    /// “15m”, “2h” or “1h 5m”.
    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(seconds, 0) / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private static func shortened(_ title: String) -> String {
        guard title.count > maxMenuBarTitleLength else { return title }
        return String(title.prefix(maxMenuBarTitleLength - 1)) + "…"
    }
}
