import XCTest
@testable import PlateCore

final class CalendarTileTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func event(_ id: String, _ calendarId: String, _ start: Date, hours: Double = 1, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, calendarId: calendarId, title: id, start: start, end: start.addingTimeInterval(hours * 3600), allDay: allDay)
    }

    func testEveryCalendarByDefault() {
        XCTAssertTrue(CalendarTileSettings.calendars([:]).isEmpty)
        XCTAssertTrue(CalendarTileSettings.shows("shared-family", options: [:]), "Shared calendars show without choosing them")
        XCTAssertEqual(CalendarTileSettings.days([:]), 7)
    }

    func testChoosingCalendars() {
        let all = ["home", "work", "shared-family"]
        var options: [String: String] = [:]
        CalendarTileSettings.toggle("work", all: all, in: &options)
        XCTAssertEqual(CalendarTileSettings.calendars(options), ["home", "shared-family"], "Unticking one keeps the rest")
        XCTAssertFalse(CalendarTileSettings.shows("work", options: options))
        XCTAssertTrue(CalendarTileSettings.shows("shared-family", options: options))

        CalendarTileSettings.toggle("work", all: all, in: &options)
        XCTAssertNil(options["cals"], "Ticking everything goes back to every calendar")

        CalendarTileSettings.setCalendars(["home"], in: &options)
        CalendarTileSettings.toggle("home", all: all, in: &options)
        XCTAssertEqual(CalendarTileSettings.calendars(options), ["home"], "The last calendar can't be unticked")
    }

    func testDaysAreKeptSensible() {
        XCTAssertEqual(CalendarTileSettings.days(["days": "3"]), 3)
        XCTAssertEqual(CalendarTileSettings.days(["days": "0"]), 1)
        XCTAssertEqual(CalendarTileSettings.days(["days": "400"]), 31)
        XCTAssertEqual(CalendarTileSettings.days(["days": "soon"]), 7)
    }

    func testWhichEventsShow() {
        let now = at(12, 14)
        let events = [
            event("finished", "home", at(12, 9)),
            event("happening", "home", at(12, 13, 30)),
            event("tonight", "shared-family", at(12, 19)),
            event("birthday", "shared-family", at(13, 0), hours: 24, allDay: true),
            event("breakfast", "home", at(13, 8)),
            event("work thing", "work", at(13, 9)),
            event("next month", "home", at(28, 9)),
        ]
        var options = ["days": "2"]
        XCTAssertEqual(CalendarTileSettings.events(events, options: options, now: now, calendar: cal).map(\.id),
                       ["happening", "tonight", "birthday", "breakfast", "work thing"],
                       "Not what's over or too far off, and all-day events first on their day")
        CalendarTileSettings.setCalendars(["shared-family"], in: &options)
        XCTAssertEqual(CalendarTileSettings.events(events, options: options, now: now, calendar: cal).map(\.id), ["tonight", "birthday"])
        options["days"] = "31"
        options["cals"] = nil
        XCTAssertTrue(CalendarTileSettings.events(events, options: options, now: now, calendar: cal).contains { $0.id == "next month" })
    }

    func testDayHeadings() {
        let now = at(12, 14) // a Thursday
        XCTAssertEqual(CalendarTileSettings.dayHeading(at(12, 20), now: now, calendar: cal), "Today")
        XCTAssertEqual(CalendarTileSettings.dayHeading(at(13, 9), now: now, calendar: cal), "Tomorrow")
        XCTAssertEqual(CalendarTileSettings.dayHeading(at(15, 9), now: now, calendar: cal), "Sunday")
        XCTAssertEqual(CalendarTileSettings.dayHeading(at(24, 9), now: now, calendar: cal), "Tue 24 Nov")
        XCTAssertEqual(CalendarTileSettings.dayHeading(at(11, 9), now: now, calendar: cal), "Today", "Something that began earlier and is still on")
    }

    func testCalendarTilesCanBeAddedMoreThanOnce() {
        XCTAssertTrue(TileKind.calendar.canRepeat, "One for the family calendar, one for work")
        var d = HomeDashboard()
        XCTAssertTrue(d.add(DashboardTile(kind: .calendar, title: "Calendar")))
        XCTAssertTrue(d.add(DashboardTile(kind: .calendar, title: "Calendar")))
        XCTAssertEqual(d.tiles.count, 2)
    }
}
