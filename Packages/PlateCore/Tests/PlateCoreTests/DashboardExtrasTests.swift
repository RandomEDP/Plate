import XCTest
@testable import PlateCore

final class DashboardExtrasTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        Calendar.plate.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Pages

    func testOnePageUntilYouAddAnother() {
        var d = HomeDashboard(tiles: [DashboardTile(kind: .clock, title: "Clock"), DashboardTile(kind: .note, title: "N")])
        XCTAssertEqual(d.pageList.count, 1)
        XCTAssertEqual(d.tiles(onPage: d.pageList[0].id).count, 2)

        let music = d.addPage(named: "Music")
        XCTAssertEqual(d.pageList.map(\.name), ["Home", "Music"])
        XCTAssertEqual(d.tiles(onPage: d.pageList[0].id).count, 2, "Existing tiles stay on the first page")
        XCTAssertTrue(d.tiles(onPage: music).isEmpty)

        d.moveTile(d.tiles[1].id, toPage: music)
        XCTAssertEqual(d.tiles(onPage: music).map(\.title), ["N"])
        XCTAssertEqual(d.tiles(onPage: d.pageList[0].id).map(\.title), ["Clock"])
    }

    func testRemovingAPageKeepsItsTiles() {
        var d = HomeDashboard(tiles: [DashboardTile(kind: .clock, title: "Clock")])
        let a = d.addPage(named: "A"), b = d.addPage(named: "")
        XCTAssertEqual(d.pageList.map(\.name), ["Home", "A", "Page 3"])
        d.add(DashboardTile(kind: .note, title: "On A", pageId: a))
        d.add(DashboardTile(kind: .note, title: "On B", pageId: b))
        d.removePage(a)
        XCTAssertEqual(d.tiles(onPage: d.pageList[0].id).map(\.title), ["Clock", "On A"])
        d.removePage(b)
        XCTAssertTrue(d.pages.isEmpty, "Back to a single page")
        XCTAssertEqual(d.tiles(onPage: d.pageList[0].id).count, 3)
        d.removePage(d.pageList[0].id)
        XCTAssertEqual(d.pageList.count, 1, "The last page can't be removed")
    }

    func testTilesOnADeletedPageShowOnTheFirst() {
        var d = HomeDashboard(tiles: [DashboardTile(kind: .note, title: "Lost", pageId: UUID())])
        d.addPage(named: "Two")
        XCTAssertEqual(d.tiles(onPage: d.pageList[0].id).map(\.title), ["Lost"])
    }

    func testTileCustomisationRoundTripsAndOldTilesStillOpen() throws {
        var t = DashboardTile(kind: .accessory, ref: "x", title: "Lamp")
        XCTAssertEqual(t.name("Hue lamp"), "Hue lamp", "Without your own name, the live HomeKit name shows")
        t.label = "Reading light"; t.icon = "book.fill"; t.tint = RGB(hex: "#FF0000"); t.options = ["a": "b"]
        XCTAssertEqual(t.name("Hue lamp"), "Reading light")
        XCTAssertEqual(try JSONDecoder().decode(DashboardTile.self, from: JSONEncoder().encode(t)), t)
        t.label = "  "
        XCTAssertEqual(t.name(), "Lamp")
        let old = try JSONDecoder().decode(DashboardTile.self, from: Data(#"{"kind":"scene","title":"Relax","ref":"s"}"#.utf8))
        XCTAssertNil(old.tint)
        XCTAssertTrue(old.options.isEmpty)
    }

    func testRepeatableTiles() {
        var d = HomeDashboard()
        XCTAssertTrue(d.add(DashboardTile(kind: .countdown, title: "Holiday")))
        XCTAssertTrue(d.add(DashboardTile(kind: .countdown, title: "Birthday")))
        XCTAssertTrue(d.add(DashboardTile(kind: .timer, title: "Timers")))
        XCTAssertFalse(d.add(DashboardTile(kind: .timer, title: "Timers")))
    }

    func testActivityKeepsTheLatestForty() {
        var d = HomeDashboard()
        for i in 0..<55 { d.log("Thing \(i)") }
        XCTAssertEqual(d.activity.count, 40)
        XCTAssertEqual(d.activity.first?.text, "Thing 54")
    }

    // MARK: Timers

    func testTimerCountsDownPausesAndResumes() {
        let t0 = day(2026, 11, 12)
        var t = DashTimer(label: "Pasta", duration: 600, startingAt: t0)
        XCTAssertEqual(t.remaining(now: t0.addingTimeInterval(60)), 540)
        XCTAssertEqual(t.progress(now: t0.addingTimeInterval(150)), 0.25, accuracy: 0.0001)
        XCTAssertFalse(t.isFinished(now: t0.addingTimeInterval(599)))
        XCTAssertTrue(t.isFinished(now: t0.addingTimeInterval(600)))

        t.pause(now: t0.addingTimeInterval(100))
        XCTAssertEqual(t.remaining(now: t0.addingTimeInterval(5000)), 500, "A paused timer doesn't move")
        XCTAssertFalse(t.isFinished(now: t0.addingTimeInterval(5000)))
        t.resume(now: t0.addingTimeInterval(1000))
        XCTAssertEqual(t.remaining(now: t0.addingTimeInterval(1100)), 400)
    }

    func testAddingTimeToARunningPausedAndFinishedTimer() {
        let t0 = day(2026, 11, 12)
        var t = DashTimer(label: "Eggs", duration: 60, startingAt: t0)
        t.add(60, now: t0.addingTimeInterval(10))
        XCTAssertEqual(t.remaining(now: t0.addingTimeInterval(10)), 110)
        t.pause(now: t0.addingTimeInterval(20))
        t.add(60, now: t0.addingTimeInterval(30))
        XCTAssertEqual(t.remaining(now: t0.addingTimeInterval(999)), 160)
        var done = DashTimer(label: "Tea", duration: 60, startingAt: t0)
        done.announced = true
        done.add(60, now: t0.addingTimeInterval(500))
        XCTAssertEqual(done.remaining(now: t0.addingTimeInterval(500)), 60, "A finished timer restarts from now")
        XCTAssertFalse(done.announced, "…and will sound again")
    }

    func testTimerText() {
        XCTAssertEqual(DashTimer.text(545), "9:05")
        XCTAssertEqual(DashTimer.text(3723), "1:02:03")
        XCTAssertEqual(DashTimer.text(0.2), "0:01", "Shows 0:01 until it's really finished")
        XCTAssertEqual(DashTimer.text(0), "0:00")
        XCTAssertEqual(DashTimer.text(-5), "0:00")
        XCTAssertEqual(DashTimer.words(600), "10 min")
        XCTAssertEqual(DashTimer.words(5400), "1 hr 30 min")
        XCTAssertEqual(DashTimer.words(45), "45 sec")
        XCTAssertEqual(DashTimer.words(90), "1 min 30 sec")
    }

    func testTimerParsing() {
        func p(_ s: String) -> String? { TimerParser.parse(s).map { "\($0.label)|\(Int($0.seconds))" } }
        XCTAssertEqual(p("pasta 10"), "Pasta|600")
        XCTAssertEqual(p("10 min"), "Timer|600")
        XCTAssertEqual(p("10m"), "Timer|600")
        XCTAssertEqual(p("1h30"), "Timer|5400")
        XCTAssertEqual(p("1h 30m"), "Timer|5400")
        XCTAssertEqual(p("1 hour 30 minutes"), "Timer|5400")
        XCTAssertEqual(p("90s"), "Timer|90")
        XCTAssertEqual(p("eggs 6m30s"), "Eggs|390")
        XCTAssertEqual(p("1:30"), "Timer|90")
        XCTAssertEqual(p("Set a timer for 5 minutes"), "Timer|300")
        XCTAssertEqual(p("roast chicken 1.5h"), "Roast chicken|5400")
        XCTAssertEqual(p("0.5"), "Timer|30")
        XCTAssertNil(p("pasta"))
        XCTAssertNil(p(""))
        XCTAssertNil(p("0"))
        XCTAssertNil(p("99h"), "Longer than a day isn't a kitchen timer")
    }

    // MARK: Chores

    func testChoresTakeTurnsEachWeek() {
        let c = Chore(name: "Bathroom", people: ["Ethan", "Sam", "Jo"], everyDays: 7, start: day(2026, 11, 9))
        XCTAssertEqual(c.assignee(on: day(2026, 11, 9)), "Ethan")
        XCTAssertEqual(c.assignee(on: day(2026, 11, 15, 23, 59)), "Ethan")
        XCTAssertEqual(c.assignee(on: day(2026, 11, 16, 0, 1)), "Sam")
        XCTAssertEqual(c.assignee(on: day(2026, 11, 23)), "Jo")
        XCTAssertEqual(c.assignee(on: day(2026, 11, 30)), "Ethan")
        XCTAssertEqual(c.assignee(on: day(2026, 11, 8)), "Jo", "Before the start it still goes round, backwards")
        XCTAssertNil(Chore(name: "X", people: [], start: day(2026, 11, 9)).assignee(on: day(2026, 11, 9)))
    }

    func testChoresAcrossTheClockChange() {
        // The clocks go forward on 28 March 2027; turns must still change at midnight on Monday.
        let c = Chore(name: "Kitchen", people: ["A", "B"], everyDays: 7, start: day(2027, 3, 22))
        XCTAssertEqual(c.assignee(on: day(2027, 3, 28, 23, 30)), "A")
        XCTAssertEqual(c.assignee(on: day(2027, 3, 29, 0, 30)), "B")
    }

    func testChoreDoneLastsUntilTheNextTurn() {
        var c = Chore(name: "Hoover", people: ["A", "B"], everyDays: 7, start: day(2026, 11, 9))
        XCTAssertFalse(c.isDone(on: day(2026, 11, 11)))
        XCTAssertEqual(c.daysLeft(on: day(2026, 11, 11)), 5)
        XCTAssertEqual(c.daysLeft(on: day(2026, 11, 15)), 1)
        c.lastDone = day(2026, 11, 11)
        XCTAssertTrue(c.isDone(on: day(2026, 11, 14)))
        XCTAssertFalse(c.isDone(on: day(2026, 11, 16)), "New week, new turn")
    }

    func testDailyChore() {
        let c = Chore(name: "Dishes", people: ["A", "B"], everyDays: 1, start: day(2026, 11, 9))
        XCTAssertEqual(c.assignee(on: day(2026, 11, 9)), "A")
        XCTAssertEqual(c.assignee(on: day(2026, 11, 10)), "B")
        XCTAssertEqual(c.assignee(on: day(2026, 11, 11)), "A")
    }

    // MARK: Bin days

    func testWeeklyAndFortnightlyBins() {
        let weekly = Recurring(name: "Food waste", everyWeeks: 1, anchor: day(2026, 11, 12))   // a Thursday
        XCTAssertEqual(weekly.next(onOrAfter: day(2026, 11, 12, 8)), Calendar.plate.startOfDay(for: day(2026, 11, 12)), "Today counts")
        XCTAssertEqual(weekly.next(onOrAfter: day(2026, 11, 13)), Calendar.plate.startOfDay(for: day(2026, 11, 19)))
        let fortnightly = Recurring(name: "Recycling", everyWeeks: 2, anchor: day(2026, 11, 12))
        XCTAssertEqual(fortnightly.next(onOrAfter: day(2026, 11, 13)), Calendar.plate.startOfDay(for: day(2026, 11, 26)))
        XCTAssertEqual(fortnightly.next(onOrAfter: day(2026, 11, 26)), Calendar.plate.startOfDay(for: day(2026, 11, 26)))
        XCTAssertEqual(fortnightly.next(onOrAfter: day(2026, 10, 1)), Calendar.plate.startOfDay(for: day(2026, 11, 12)),
                       "Before the first one, the first one is next")
    }

    func testDayWording() {
        let now = day(2026, 11, 12)   // Thursday
        XCTAssertEqual(DayText.relative(day(2026, 11, 12, 23), now: now), "Today")
        XCTAssertEqual(DayText.relative(day(2026, 11, 13, 0, 5), now: now), "Tomorrow")
        XCTAssertEqual(DayText.relative(day(2026, 11, 11), now: now), "Yesterday")
        XCTAssertEqual(DayText.relative(day(2026, 11, 16), now: now), "Monday")
        XCTAssertEqual(DayText.relative(day(2026, 11, 26), now: now), "Thu 26 Nov")
        XCTAssertEqual(DayText.weekday(now), "Thursday")
    }

    func testCountdown() {
        let now = day(2026, 11, 12)
        XCTAssertEqual(DayText.countdown(to: day(2026, 12, 25), now: now).number, "43")
        XCTAssertEqual(DayText.countdown(to: day(2026, 12, 25), now: now).caption, "days to go")
        XCTAssertEqual(DayText.countdown(to: day(2026, 11, 13, 1), now: now).caption, "day to go")
        XCTAssertEqual(DayText.countdown(to: day(2026, 11, 12, 23), now: now).number, "Today")
        XCTAssertEqual(DayText.countdown(to: day(2026, 11, 2), now: now).number, "10")
        XCTAssertEqual(DayText.countdown(to: day(2026, 11, 2), now: now).caption, "days ago")
    }

    // MARK: Wording

    func testGreeting() {
        XCTAssertEqual(DayText.greeting(hour: 7, name: "Ethan"), "Good morning, Ethan")
        XCTAssertEqual(DayText.greeting(hour: 12), "Good afternoon")
        XCTAssertEqual(DayText.greeting(hour: 19, name: " "), "Good evening")
        XCTAssertEqual(DayText.greeting(hour: 2, name: "Me"), "Good night", "The placeholder name isn't used")
    }

    func testSummaryLine() {
        XCTAssertEqual(DayText.summary(lightsOn: 3, inside: 20.46, outside: 8.6, rain: "Rain likely from 15:00", timers: 1, choresDue: 2),
                       "3 lights on · 20.5° inside · 9° outside · Rain likely from 15:00 · 1 timer running · 2 chores due")
        XCTAssertEqual(DayText.summary(lightsOn: 0, inside: nil, outside: nil, rain: nil, timers: 0, choresDue: 0), "All lights off")
        XCTAssertEqual(DayText.summary(lightsOn: nil, inside: nil, outside: nil, rain: nil, timers: 0, choresDue: 0), "")
    }

    func testClockInWords() {
        XCTAssertEqual(DayText.clockWords(hour: 16, minute: 20), "twenty past four")
        XCTAssertEqual(DayText.clockWords(hour: 16, minute: 22), "twenty past four")
        XCTAssertEqual(DayText.clockWords(hour: 16, minute: 23), "twenty-five past four")
        XCTAssertEqual(DayText.clockWords(hour: 8, minute: 45), "quarter to nine")
        XCTAssertEqual(DayText.clockWords(hour: 12, minute: 30), "half past midday")
        XCTAssertEqual(DayText.clockWords(hour: 9, minute: 0), "nine o'clock")
        XCTAssertEqual(DayText.clockWords(hour: 23, minute: 58), "midnight")
        XCTAssertEqual(DayText.clockWords(hour: 0, minute: 2), "midnight")
        XCTAssertEqual(DayText.clockWords(hour: 11, minute: 40), "twenty to midday")
        XCTAssertEqual(DayText.clockWords(hour: 12, minute: 58), "one o'clock")
        XCTAssertEqual(DayText.clockWords(hour: 23, minute: 5), "five past eleven")
    }

    func testBriefing() {
        XCTAssertEqual(Briefing.text(greeting: "Good morning, Ethan", weather: "It's 9 degrees and cloudy.", rain: "Rain likely from 15:00",
                                     meals: ["porridge", "chicken orzo"], chores: ["bathroom"], bins: ["Recycling goes out today"], timers: 0),
                       "Good morning, Ethan. It's 9 degrees and cloudy. Rain likely from 15:00. On the plan today: porridge and chicken orzo. Chores due: bathroom. Recycling goes out today.")
        XCTAssertEqual(Briefing.text(greeting: "Good evening", weather: nil, rain: nil, meals: [], chores: [], bins: [], timers: 2),
                       "Good evening. 2 timers are running.")
        XCTAssertEqual(Briefing.list(["a", "b", "c"]), "a, b and c")
    }

    // MARK: Routines

    func testRoutineSummaries() {
        XCTAssertEqual(RoutineAction(kind: .accessoryOn, ref: "1", name: "Lamp").summary, "Turn on Lamp")
        XCTAssertEqual(RoutineAction(kind: .brightness, ref: "1", name: "Lamp", value: 30).summary, "Set Lamp to 30%")
        XCTAssertEqual(RoutineAction(kind: .wait, value: 30).summary, "Wait 30 sec")
        XCTAssertEqual(RoutineAction(kind: .startTimer, value: 600, text: "Pasta").summary, "Start a 10 min timer (Pasta)")
        XCTAssertEqual(RoutineAction(kind: .say, text: "Dinner's ready").summary, "Say “Dinner's ready”")
        XCTAssertEqual(RoutineAction(kind: .lightShow, text: "candle").summary, "Start the candlelight light show")
    }

    func testRoutineSkipsActionsFromANewerVersion() throws {
        let json = """
        {"name":"Movie night","actions":[{"kind":"scene","ref":"s","name":"Film"},{"kind":"teleport","ref":"x"},{"kind":"say","text":"Enjoy"}]}
        """
        let r = try JSONDecoder().decode(Routine.self, from: Data(json.utf8))
        XCTAssertEqual(r.actions.map(\.kind), [.scene, .say])
        let back = try JSONDecoder().decode(Routine.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.actions, r.actions)
    }

    func testScheduleAtASetTime() {
        let s = RoutineSchedule(routineId: UUID(), minutes: 7 * 60)
        let seven = day(2026, 11, 12, 7, 0)
        XCTAssertFalse(s.isDue(lastCheck: day(2026, 11, 12, 6, 58), now: day(2026, 11, 12, 6, 59), sunrise: nil, sunset: nil))
        XCTAssertTrue(s.isDue(lastCheck: day(2026, 11, 12, 6, 59), now: seven, sunrise: nil, sunset: nil))
        XCTAssertFalse(s.isDue(lastCheck: seven, now: day(2026, 11, 12, 7, 1), sunrise: nil, sunset: nil), "Only once")
        XCTAssertTrue(s.isDue(lastCheck: day(2026, 11, 12, 6, 0), now: day(2026, 11, 12, 7, 8), sunrise: nil, sunset: nil), "A few minutes late is fine")
        XCTAssertFalse(s.isDue(lastCheck: day(2026, 11, 11, 22, 0), now: day(2026, 11, 12, 9, 0), sunrise: nil, sunset: nil),
                       "Hours late (the app was closed) doesn't run it")
        var off = s; off.enabled = false
        XCTAssertFalse(off.isDue(lastCheck: day(2026, 11, 12, 6, 59), now: seven, sunrise: nil, sunset: nil))
    }

    func testScheduleOnWeekdaysOnly() {
        let s = RoutineSchedule(routineId: UUID(), minutes: 7 * 60, weekdays: [2, 3, 4, 5, 6])
        XCTAssertTrue(s.isDue(lastCheck: day(2026, 11, 12, 6, 59), now: day(2026, 11, 12, 7, 0), sunrise: nil, sunset: nil))   // Thursday
        XCTAssertFalse(s.isDue(lastCheck: day(2026, 11, 14, 6, 59), now: day(2026, 11, 14, 7, 0), sunrise: nil, sunset: nil))  // Saturday
        XCTAssertEqual(s.summary, "07:00 on weekdays")
    }

    func testScheduleAtSunset() {
        let sunset = day(2026, 11, 12, 16, 12)
        let s = RoutineSchedule(routineId: UUID(), sun: .sunset, offset: -15)
        XCTAssertEqual(s.fireTime(on: day(2026, 11, 12), sunrise: nil, sunset: sunset), day(2026, 11, 12, 15, 57))
        XCTAssertTrue(s.isDue(lastCheck: day(2026, 11, 12, 15, 56), now: day(2026, 11, 12, 15, 57), sunrise: nil, sunset: sunset))
        XCTAssertFalse(s.isDue(lastCheck: day(2026, 11, 12, 15, 56), now: day(2026, 11, 12, 15, 57), sunrise: nil, sunset: nil),
                       "No sun times yet (no weather): it waits")
        XCTAssertNil(s.fireTime(on: day(2026, 11, 13), sunrise: nil, sunset: sunset), "Yesterday's sunset isn't used for today")
        XCTAssertEqual(s.summary, "Sunset −15 min every day")
        XCTAssertEqual(RoutineSchedule(routineId: UUID(), minutes: 22 * 60 + 30, weekdays: [1, 7]).summary, "22:30 at weekends")
        XCTAssertEqual(RoutineSchedule(routineId: UUID(), sun: .sunrise, weekdays: [2, 6]).summary, "Sunrise on Mon, Fri")
    }

    // MARK: Lights

    func testLightShowColoursStayInRange() {
        for show in LightShow.allCases {
            XCTAssertGreaterThanOrEqual(show.interval, 1.5, "\(show): HomeKit bulbs can't change faster")
            for step in 0..<200 {
                for light in 0..<5 {
                    let c = show.color(step: step, light: light, of: 5)
                    XCTAssertTrue((0..<360.0001).contains(c.hue), "\(show) hue \(c.hue)")
                    XCTAssertTrue((0...100).contains(c.saturation), "\(show) saturation \(c.saturation)")
                    XCTAssertTrue((1...100).contains(c.brightness), "\(show) brightness \(c.brightness)")
                }
            }
        }
    }

    func testPartyNeverRepeatsAColourOnALight() {
        for light in 0..<4 {
            for step in 0..<300 {
                XCTAssertNotEqual(LightShow.party.color(step: step, light: light, of: 4).hue,
                                  LightShow.party.color(step: step + 1, light: light, of: 4).hue, "light \(light) step \(step)")
            }
        }
    }

    func testCandleIsWarmAndDim() {
        for step in 0..<100 {
            let c = LightShow.candle.color(step: step, light: 0, of: 1)
            XCTAssertTrue((25...40).contains(c.hue))
            XCTAssertLessThanOrEqual(c.brightness, 65)
        }
    }

    func testColourTemperature() {
        XCTAssertEqual(LightColor.mired(kelvin: 2700), 370)
        XCTAssertEqual(LightColor.mired(kelvin: 6500), 154)
        XCTAssertEqual(LightColor.mired(kelvin: 2000), 500)
        XCTAssertEqual(LightColor.mired(kelvin: 10_000), 140, "Kept inside what the bulb can do")
        XCTAssertEqual(LightColor.mired(kelvin: 2000, min: 153, max: 454), 454)
    }

    func testNextSunEvent() {
        let rise = day(2026, 11, 12, 7, 15), set = day(2026, 11, 12, 16, 12), next = day(2026, 11, 13, 7, 17)
        XCTAssertEqual(WeatherText.nextSun(sunrise: rise, sunset: set, tomorrowSunrise: next, now: day(2026, 11, 12, 6))?.title, "Sunrise")
        XCTAssertEqual(WeatherText.nextSun(sunrise: rise, sunset: set, tomorrowSunrise: next, now: day(2026, 11, 12, 12))?.at, set)
        XCTAssertEqual(WeatherText.nextSun(sunrise: rise, sunset: set, tomorrowSunrise: next, now: day(2026, 11, 12, 20))?.at, next)
        XCTAssertNil(WeatherText.nextSun(sunrise: nil, sunset: nil, tomorrowSunrise: nil, now: day(2026, 11, 12)))
    }

    func testClockHands() {
        let three = WeatherText.clockAngles(hour: 15, minute: 0)
        XCTAssertEqual(three.hour, 90); XCTAssertEqual(three.minute, 0)
        let halfSix = WeatherText.clockAngles(hour: 6, minute: 30, second: 30)
        XCTAssertEqual(halfSix.hour, 195.25, accuracy: 0.001)
        XCTAssertEqual(halfSix.minute, 183)
        XCTAssertEqual(halfSix.second, 180)
    }

    func testIdleExtrasDefaultForOldFiles() throws {
        let s = try JSONDecoder().decode(IdleSettings.self, from: Data(#"{"minutes":5}"#.utf8))
        XCTAssertEqual(s.clockFace, .digital)
        XCTAssertTrue(s.showWeather)
        XCTAssertFalse(s.wakeOnMotion)
    }

    // MARK: Odds and ends

    func testWiFiCode() {
        XCTAssertEqual(WiFiQR.payload(ssid: "Flat 4", password: "hunter22"), "WIFI:T:WPA;S:Flat 4;P:hunter22;;")
        XCTAssertEqual(WiFiQR.payload(ssid: "Open", password: ""), "WIFI:T:nopass;S:Open;;")
        XCTAssertEqual(WiFiQR.payload(ssid: "A;B", password: #"p:a\s,"s"#), #"WIFI:T:WPA;S:A\;B;P:p\:a\\s\,\"s;;"#)
        XCTAssertEqual(WiFiQR.payload(ssid: "Hidden", password: "x", hidden: true), "WIFI:T:WPA;S:Hidden;P:x;H:true;;")
    }

    func testBurnInDriftIsSmallAndMoves() {
        let t0 = day(2026, 11, 12)
        var seen = Set<String>()
        for m in 0..<120 {
            let o = IdleMode.burnInOffset(t0.addingTimeInterval(Double(m) * 60), radius: 12)
            XCTAssertLessThanOrEqual(abs(o.x), 12.0001)
            XCTAssertLessThanOrEqual(abs(o.y), 12.0001)
            seen.insert("\(Int(o.x.rounded())),\(Int(o.y.rounded()))")
        }
        XCTAssertGreaterThan(seen.count, 30, "It keeps moving")
        let a = IdleMode.burnInOffset(t0.addingTimeInterval(5)), b = IdleMode.burnInOffset(t0.addingTimeInterval(50))
        XCTAssertEqual(a.x, b.x, "Still within a minute, so nothing jitters")
    }

    func testDashboardWithEverythingRoundTrips() throws {
        var d = HomeDashboard()
        d.style = ThemePreset.all[3].style
        d.addPage(named: "Music")
        d.timers = [DashTimer(label: "Pasta", duration: 600, startingAt: day(2026, 11, 12))]
        d.chores = [Chore(name: "Bins", people: ["A", "B"], start: day(2026, 11, 9))]
        d.recurring = [Recurring(name: "Recycling", tint: RGB(hex: "#0000FF"), everyWeeks: 2, anchor: day(2026, 11, 12))]
        let r = Routine(name: "Night", actions: [RoutineAction(kind: .allLightsOff), RoutineAction(kind: .say, text: "Night")])
        d.routines = [r]
        d.schedules = [RoutineSchedule(routineId: r.id, sun: .sunset, offset: 10, weekdays: [1, 7])]
        d.log("Lamp on", at: day(2026, 11, 12))
        let back = try JSONDecoder().decode(HomeDashboard.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
    }
}
