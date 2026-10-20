import Foundation
import Testing
@testable import Launch

struct CalendarAgendaTests {
    private let midnight = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    private func at(_ hours: Double) -> Date {
        midnight.addingTimeInterval(hours * 3600)
    }

    private func event(_ title: String, from start: Double, to end: Double, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: title, title: title, start: at(start), end: at(end), isAllDay: allDay)
    }

    @Test func eventsOverlappingTheDayAreKeptAndSorted() {
        let day = DateInterval(start: midnight, end: at(24))
        let events = [
            event("Late", from: 15, to: 16),
            event("Early", from: 9, to: 10),
            event("Overnight", from: -2, to: 1),
            event("Tomorrow", from: 25, to: 26),
            event("Holiday", from: 0, to: 24, allDay: true),
        ]

        let titles = CalendarAgenda.events(overlapping: day, in: events).map(\.title)

        #expect(titles == ["Holiday", "Overnight", "Early", "Late"])
    }

    @Test func featuredIsTheNextTimedEventWhenNothingIsOnNow() {
        let events = [
            event("Done", from: 8, to: 9),
            event("Lunch", from: 12, to: 13),
            event("Standup", from: 10, to: 10.25),
            event("Holiday", from: 0, to: 24, allDay: true),
        ]

        #expect(CalendarAgenda.featuredEvent(in: events, now: at(9.5))?.title == "Standup")
    }

    @Test func anEventInProgressIsFeaturedUntilItEnds() {
        let events = [event("Now", from: 9, to: 11), event("Next", from: 12, to: 13)]

        #expect(CalendarAgenda.featuredEvent(in: events, now: at(10))?.title == "Now")
        #expect(CalendarAgenda.featuredEvent(in: events, now: at(11))?.title == "Next")
    }

    @Test func noFeaturedEventWhenTheDayIsOver() {
        let events = [event("Done", from: 8, to: 9), event("Holiday", from: 0, to: 24, allDay: true)]

        #expect(CalendarAgenda.featuredEvent(in: events, now: at(20)) == nil)
    }

    @Test func menuBarTitleCountsDownWhileAnEventRuns() {
        let testEvent = event("test event", from: 10, to: 10.5)

        #expect(CalendarAgenda.menuBarTitle(for: testEvent, now: at(10) + 60) == "test event • 29m left")
    }

    @Test func menuBarTitleSaysHowSoonAnEventStarts() {
        let standup = event("Standup", from: 10, to: 10.25)

        #expect(CalendarAgenda.menuBarTitle(for: standup, now: at(9.75)) == "Standup • in 15m")
        #expect(CalendarAgenda.menuBarTitle(for: standup, now: at(9)) == "Standup • in 1h")
    }

    @Test func rowTimingCountsDownWhileAnEventRuns() {
        let standup = event("Standup", from: 10, to: 10.5)

        #expect(CalendarAgenda.timingText(for: standup, now: at(9.75)) == "in 15m")
        #expect(CalendarAgenda.timingText(for: standup, now: at(10) + 60 * 22) == "8m left")
        #expect(CalendarAgenda.timingText(for: standup, now: at(10.5)) == nil)
    }

    @Test func dismissalsEndWithTheirEvent() {
        let dismissed = ["ended": at(9), "running": at(11)]

        #expect(CalendarAgenda.pruned(dismissed, now: at(10)) == ["running": at(11)])
    }

    @Test func longTitlesAreCutInTheMenuBar() throws {
        let long = event(String(repeating: "A", count: 40), from: 10, to: 11)

        let title = CalendarAgenda.menuBarTitle(for: long, now: at(9))
        let shown = try #require(title.components(separatedBy: " • ").first)

        #expect(shown.count == CalendarAgenda.maxMenuBarTitleLength)
        #expect(shown.hasSuffix("…"))
    }

    @Test func timedEventsShowTheirStartAndEnd() {
        let standup = event("Standup", from: 10, to: 10.25)
        let start = standup.start.formatted(date: .omitted, time: .shortened)
        let end = standup.end.formatted(date: .omitted, time: .shortened)

        #expect(CalendarAgenda.timeText(for: standup) == "\(start) – \(end)")
    }

    @Test func allDayEventsReadAsAllDay() {
        #expect(CalendarAgenda.timeText(for: event("Holiday", from: 0, to: 24, allDay: true)) == "All day")
    }

    @Test func calendarURLOpensTheEventInCalendar() throws {
        var standup = event("Standup", from: 10, to: 10.25)
        standup.calendarItemIdentifier = "ABC:1"

        let url = try #require(CalendarAgenda.calendarURL(for: standup))
        let text = url.absoluteString

        #expect(text.hasPrefix("ical://ekevent/"))
        #expect(text.hasSuffix("/ABC%3A1?method=show&options=more"))
        #expect(text.range(of: #"/\d{8}T\d{6}Z/"#, options: .regularExpression) != nil)
    }

    @Test func eventWithoutAnIdentifierHasNoCalendarLink() {
        let standup = event("Standup", from: 10, to: 10.25)

        #expect(CalendarAgenda.calendarURL(for: standup) == nil)
    }

    @Test func meetingLinkFromNotesBeatsTheEventURL() throws {
        let event = URL(string: "https://example.com/event")!

        let url = CalendarAgenda.meetingURL(url: event, texts: ["Room 4", "Join: https://acme.zoom.us/j/123 please"])

        #expect(url?.host == "acme.zoom.us")
    }

    @Test func knownMeetingServicesAreRecognisedInTheLocation() throws {
        let url = CalendarAgenda.meetingURL(url: nil, texts: ["https://meet.google.com/abc-defg-hij", ""])

        #expect(url?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func otherWebURLIsUsedWhenNoMeetingServiceIsLinked() throws {
        let event = URL(string: "https://example.com/agenda")!

        #expect(CalendarAgenda.meetingURL(url: event, texts: ["No link here"]) == event)
    }

    @Test func noLinkMeansNoMeetingURL() {
        #expect(CalendarAgenda.meetingURL(url: URL(string: "mailto:a@b.c"), texts: ["Lunch"]) == nil)
    }

    @Test func clickOpensTheMeetingWhenThereIsOne() throws {
        var standup = event("Standup", from: 10, to: 10.25)
        standup.meetingURL = URL(string: "https://zoom.us/j/1")

        #expect(CalendarAgenda.openTarget(for: standup) == standup.meetingURL)
    }

    @Test func clickOpensCalendarWhenThereIsNoMeeting() throws {
        let standup = event("Standup", from: 10, to: 10.25)

        #expect(CalendarAgenda.openTarget(for: standup) == CalendarAgenda.calendarURL(for: standup))
    }
}
