import XCTest
@testable import PlateCore

/// The calendar tile can also show reminders from chosen Reminders lists (a shared household list, say).
final class CalendarRemindersTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(15, 13) }

    private func ids(_ items: [AgendaItem]) -> [String] { items.map(\.id) }

    func testNoRemindersUntilAListIsChosen() {
        let r = ReminderItem(id: "milk", listId: "home", title: "Milk", due: at(15, 18), dueHasTime: true)
        XCTAssertTrue(CalendarTileSettings.agenda(events: [], reminders: [r], options: [:], now: now, calendar: cal).isEmpty)
        var options: [String: String] = [:]
        CalendarTileSettings.toggleReminderList("home", in: &options)
        XCTAssertEqual(ids(CalendarTileSettings.agenda(events: [], reminders: [r], options: options, now: now, calendar: cal)), ["r-milk"])
        CalendarTileSettings.toggleReminderList("home", in: &options)
        XCTAssertNil(options["rlists"], "Unticking the last list turns reminders off again")
    }

    func testEventsAndRemindersMixedByDayAndTime() {
        let options = ["rlists": "home"]
        let events = [
            CalendarEvent(id: "shed", calendarId: "c", title: "Chicken shed", start: at(15, 9), end: at(15, 21)),
            CalendarEvent(id: "goose", calendarId: "c", title: "Goose United", start: at(15, 18), end: at(15, 19)),
            CalendarEvent(id: "birthday", calendarId: "c", title: "Birthday", start: at(16, 0), end: at(17, 0), allDay: true),
        ]
        let reminders = [
            ReminderItem(id: "bins", listId: "home", title: "Bins out", due: at(15, 0), dueHasTime: false),
            ReminderItem(id: "call", listId: "home", title: "Call landlord", due: at(15, 17), dueHasTime: true),
            ReminderItem(id: "late", listId: "home", title: "Pay rent", due: at(13, 0), dueHasTime: false),
            ReminderItem(id: "gas", listId: "home", title: "Gas reading", due: at(16, 10), dueHasTime: true),
            ReminderItem(id: "other", listId: "work", title: "Not shown", due: at(15, 12), dueHasTime: true),
            ReminderItem(id: "someday", listId: "home", title: "Fix shelf"),
            ReminderItem(id: "far", listId: "home", title: "Too far", due: at(30, 9), dueHasTime: true),
        ]
        let items = CalendarTileSettings.agenda(events: events, reminders: reminders, options: options, now: now, calendar: cal)
        XCTAssertEqual(ids(items), ["r-late", "r-bins", "e-shed", "r-call", "e-goose", "e-birthday", "r-gas"])
        XCTAssertEqual(items[0].day(now: now, calendar: cal), at(15, 0), "Overdue shows under today")
    }

    func testOverdue() {
        XCTAssertTrue(ReminderItem(id: "a", listId: "l", title: "a", due: at(15, 12), dueHasTime: true).isOverdue(now: now, calendar: cal))
        XCTAssertFalse(ReminderItem(id: "b", listId: "l", title: "b", due: at(15, 0), dueHasTime: false).isOverdue(now: now, calendar: cal),
                       "Due today with no time isn't late yet")
        XCTAssertTrue(ReminderItem(id: "c", listId: "l", title: "c", due: at(14, 0)).isOverdue(now: now, calendar: cal))
        XCTAssertFalse(ReminderItem(id: "d", listId: "l", title: "d").isOverdue(now: now, calendar: cal))
    }

    func testUndatedRemindersImportantFirst() {
        let reminders = [
            ReminderItem(id: "1", listId: "home", title: "washing up liquid"),
            ReminderItem(id: "2", listId: "home", title: "Batteries", priority: 1),
            ReminderItem(id: "3", listId: "home", title: "Bulbs"),
            ReminderItem(id: "4", listId: "home", title: "Dated", due: at(15, 18), dueHasTime: true),
            ReminderItem(id: "5", listId: "work", title: "Other list"),
        ]
        XCTAssertEqual(CalendarTileSettings.undated(reminders, options: ["rlists": "home"]).map(\.id), ["2", "3", "1"])
        XCTAssertTrue(CalendarTileSettings.undated(reminders, options: ["rlists": "home", "undated": "0"]).isEmpty)
    }
}

/// The "Today's list" tile: today's reminders, repeating ones included, as bullets.
final class TodaysListTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testTodaysListOrder() {
        let now = at(19, 13)   // a Thursday
        let reminders = [
            ReminderItem(id: "shake", listId: "home", title: "Drink a protein shake", due: at(19, 0)),
            ReminderItem(id: "bins", listId: "home", title: "Take the bins out", due: at(19, 19), dueHasTime: true),
            ReminderItem(id: "plants", listId: "home", title: "Water plants", due: at(18, 0)),
            ReminderItem(id: "pills", listId: "home", title: "Vitamins", due: at(19, 9), dueHasTime: true),
            ReminderItem(id: "tomorrow", listId: "home", title: "Tomorrow's", due: at(20, 9), dueHasTime: true),
            ReminderItem(id: "shelf", listId: "home", title: "Fix shelf"),
            ReminderItem(id: "work", listId: "work", title: "Other list", due: at(19, 0)),
        ]
        let list = CalendarTileSettings.dueToday(reminders, options: ["rlists": "home"], now: now, calendar: cal)
        XCTAssertEqual(list.map(\.id), ["plants", "pills", "shake", "bins", "shelf"],
                       "Overdue first, then today's untimed, then by time, then undated")
        let datedOnly = CalendarTileSettings.dueToday(reminders, options: ["rlists": "home", "undated": "0"], now: now, calendar: cal)
        XCTAssertFalse(datedOnly.contains { $0.id == "shelf" })
        XCTAssertTrue(CalendarTileSettings.dueToday(reminders, options: [:], now: now, calendar: cal).isEmpty, "No list chosen yet")
    }

    func testRepeatWording() {
        let thursday = at(19, 9)
        XCTAssertEqual(ReminderRepeat.weekly.title(startingOn: thursday, calendar: cal), "Every Thursday")
        XCTAssertEqual(ReminderRepeat.fortnightly.title(startingOn: thursday, calendar: cal), "Every other Thursday")
        XCTAssertEqual(ReminderRepeat.daily.title(startingOn: thursday, calendar: cal), "Every day")
        XCTAssertEqual(ReminderRepeat.never.title(startingOn: thursday, calendar: cal), "Just once")
    }

    func testTheListTileOpensUp() {
        XCTAssertEqual(TileTap.action(for: .checklist), .details)
        XCTAssertEqual(DashboardTile.defaultSize(for: .checklist), .tall)
        XCTAssertTrue(TileKind.checklist.canRepeat)
    }
}
