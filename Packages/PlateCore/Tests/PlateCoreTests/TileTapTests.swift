import XCTest
@testable import PlateCore

/// Tapping a tile that isn't a button shows more about it.
final class TileTapTests: XCTestCase {
    func testWhatEachTileDoesWhenTapped() {
        XCTAssertEqual(TileTap.action(for: .weather), .details)
        XCTAssertEqual(TileTap.action(for: .forecast), .details)
        XCTAssertEqual(TileTap.action(for: .calendar), .details)
        XCTAssertEqual(TileTap.action(for: .nowPlaying), .details)
        XCTAssertEqual(TileTap.action(for: .wifi), .details)
        XCTAssertEqual(TileTap.action(for: .shoppingList), .open(.shop))
        XCTAssertEqual(TileTap.action(for: .todaysMeals), .open(.plan))
        XCTAssertEqual(TileTap.action(for: .useSoon), .open(.kitchen))
    }

    func testButtonsKeepTheirOwnTap() {
        // These switch something or have their own buttons, so a tap must still do that.
        for kind in [TileKind.accessory, .scene, .room, .musicAlbum, .playlist, .allOff, .camera, .routine, .lightShow, .shortcut,
                     .briefing, .group, .timer, .chores, .command, .folder, .trains, .spacer, .heading, .unknown] {
            XCTAssertEqual(TileTap.action(for: kind), .none, "\(kind)")
        }
    }

    func testEveryKindHasAnAnswer() {
        // Nothing crashes for a kind added later; it just does nothing until it's given a view.
        for kind in TileKind.allCases { _ = TileTap.action(for: kind) }
    }

    func testDayBarsSitOnTheWeeksRange() {
        let s = WeatherText.span(low: 5, high: 10, weekLow: 0, weekHigh: 20)
        XCTAssertEqual(s.start, 0.25, accuracy: 0.001)
        XCTAssertEqual(s.end, 0.5, accuracy: 0.001)
        let same = WeatherText.span(low: 20, high: 20, weekLow: 0, weekHigh: 20)
        XCTAssertEqual(same.end - same.start, 0.04, accuracy: 0.001, "Never too thin to see")
        XCTAssertLessThanOrEqual(same.end, 1)
        let flat = WeatherText.span(low: 8, high: 8, weekLow: 8, weekHigh: 8)
        XCTAssertEqual(flat.start, 0); XCTAssertEqual(flat.end, 1)
    }

    func testNextHoursStartFromThisHour() {
        let cal = Calendar.plate
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12, minute: 33))!
        let hours = (0..<30).map { i in
            HourForecast(date: cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10))!.addingTimeInterval(Double(i) * 3600),
                         temperature: Double(i), precipitationChance: 0)
        }.shuffled()
        let next = WeatherText.nextHours(hours, now: now, count: 24)
        XCTAssertEqual(next.count, 24)
        XCTAssertEqual(next.first?.temperature, 2, "12:00, the hour we're in")
        XCTAssertEqual(next.last?.temperature, 25)
    }

    func testBinDaysAhead() {
        let cal = Calendar.plate
        let thursday = cal.date(from: DateComponents(year: 2026, month: 11, day: 12))!
        let sunday = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 9))!
        let fortnightly = Recurring(name: "Recycling", everyWeeks: 2, anchor: thursday)
        let days = fortnightly.upcoming(3, from: sunday)
        XCTAssertEqual(days.map { cal.component(.day, from: $0) }, [26, 10, 24])
        let weekly = Recurring(name: "Rubbish", anchor: sunday)
        XCTAssertEqual(weekly.upcoming(2, from: sunday).map { cal.component(.day, from: $0) }, [15, 22], "Today counts")
    }
}
