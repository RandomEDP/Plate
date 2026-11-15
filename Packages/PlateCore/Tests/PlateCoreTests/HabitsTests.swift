import XCTest
@testable import PlateCore

/// Tracking today's list from what's been ticked off in Reminders.
final class HabitsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private let options = ["rlists": "home"]

    func testStreakAndWeek() {
        let now = at(19, 13)   // Thursday
        var done = [17, 18, 19, 15, 12, 1].map { ReminderDone(title: "Drink a protein shake", listId: "home", completed: at($0)) }
        done.append(ReminderDone(title: "drink a  protein shake ", listId: "home", completed: at(19, 8)))   // twice today: one day
        done.append(ReminderDone(title: "Take the bins out", listId: "home", completed: at(12, 19)))
        done.append(ReminderDone(title: "Work thing", listId: "work", completed: at(19)))
        done.append(ReminderDone(title: "Old", listId: "home", completed: at(19).addingTimeInterval(-40 * 86_400)))
        let stats = Habits.stats(done, options: options, now: now, calendar: cal)
        XCTAssertEqual(stats.map(\.title), ["Drink a protein shake", "Take the bins out"])
        let shake = stats[0]
        XCTAssertEqual(shake.lastSeven, 4, "13th to 19th: 15, 17, 18, 19")
        XCTAssertEqual(shake.lastThirty, 6)
        XCTAssertEqual(shake.streak, 3)
        XCTAssertTrue(shake.doneToday)
        XCTAssertEqual(Habits.summary(shake, now: now, calendar: cal), "Done 4 of the last 7 days · 3 days in a row")
        XCTAssertEqual(Habits.summary(stats[1], now: now, calendar: cal), "Last done Thu 12 Nov")
        XCTAssertEqual(Habits.streak(for: "DRINK a protein shake", in: stats), 3)
        XCTAssertNil(Habits.streak(for: "Take the bins out", in: stats), "A one-off isn't a streak")
    }

    func testStreakSurvivesUntilTodayIsDone() {
        let days: Set<Date> = [cal.startOfDay(for: at(17)), cal.startOfDay(for: at(18))]
        XCTAssertEqual(Habits.streak(days, today: cal.startOfDay(for: at(19)), calendar: cal), 2, "Not done yet today")
        XCTAssertEqual(Habits.streak(days, today: cal.startOfDay(for: at(20)), calendar: cal), 0, "Missed a day")
    }

    func testNothingFromListsNotChosen() {
        let done = [ReminderDone(title: "A", listId: "home", completed: at(19))]
        XCTAssertTrue(Habits.stats(done, options: [:], now: at(19, 13), calendar: cal).isEmpty)
    }
}
